extends Node

# 네트워크 매니저 - 멀티플레이어 게임 관리

signal player_connected(id, player_info)
signal player_disconnected(id)
signal game_state_changed(new_state)
signal question_received(player_id, questions)
signal all_questions_ready()
signal score_updated(player_id, score)
signal all_scores_received(scores_data)

const PORT = 7000
const MAX_PLAYERS = 5

var is_server = false
var player_info = {"name": "", "id": 0}
var connected_players = {}  # {id: {name: "", questions: []}}
var game_host_ip = ""

func _ready():
	# 멀티플레이어 시그널 연결
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func create_server():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		print("서버 생성 실패: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_server = true
	player_info.id = 1
	connected_players[1] = player_info.duplicate()
	
	print("서버가 시작되었습니다. IP: ", get_local_ip())
	return true

func join_server(ip: String):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	if error != OK:
		print("서버 연결 실패: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_server = false
	game_host_ip = ip
	
	print("서버에 연결을 시도합니다: ", ip)
	return true

func set_player_name(player_name: String):
	player_info.name = player_name
	if is_server:
		# 서버(호스트)인 경우 직접 업데이트
		connected_players[1] = player_info.duplicate()
		player_connected.emit(1, player_info)
	
	if multiplayer.multiplayer_peer:
		rpc("update_player_info", multiplayer.get_unique_id(), player_info)

@rpc("any_peer", "call_local")
func update_player_info(id: int, info: Dictionary):
	connected_players[id] = info
	player_connected.emit(id, info)
	print("플레이어 정보 업데이트: ", info.name, " (ID: ", id, ")")
	print("현재 총 플레이어 수: ", connected_players.size())

@rpc("any_peer", "call_local")
func submit_questions(questions: Array):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:  # 로컬 호스트인 경우
		sender_id = 1
	
	print("질문 제출 - 발신자 ID: ", sender_id)
	print("연결된 플레이어들: ", connected_players.keys())
	
	if sender_id in connected_players:
		connected_players[sender_id]["questions"] = questions
		question_received.emit(sender_id, questions)
		print("질문 수신: ", connected_players[sender_id].name, " - ", questions.size(), "개")
		
		# 모든 플레이어가 질문을 제출했는지 확인
		check_all_questions_ready()
	else:
		print("경고: 발신자 ID ", sender_id, "가 연결된 플레이어 목록에 없습니다!")

func check_all_questions_ready():
	print("질문 제출 상태 확인 중...")
	var ready_count = 0
	var total_count = connected_players.size()
	
	for player_id in connected_players:
		var player = connected_players[player_id]
		if player.has("questions") and player.questions.size() > 0:
			ready_count += 1
			print("  - ", player.name, ": 질문 ", player.questions.size(), "개 제출됨")
		else:
			print("  - ", player.name, ": 질문 미제출")
	
	print("진행 상황: %d/%d 플레이어가 질문 제출 완료" % [ready_count, total_count])
	
	if ready_count == total_count and total_count > 0:
		print("모든 플레이어의 질문이 준비되었습니다!")
		all_questions_ready.emit()
		
		# 서버(호스트)만 클라이언트들에게 퀴즈 시작 신호를 보냄
		if is_server:
			print("호스트가 모든 클라이언트에게 퀴즈 시작 신호를 보냅니다.")
			rpc("start_game_phase", "START_QUIZ", {"all_questions": get_all_questions_data()})
		
		return true
	
	return false

func get_all_questions_data():
	# 모든 질문 데이터를 수집하여 클라이언트에게 전송
	var all_questions_data = []
	for player_id in connected_players:
		var player = connected_players[player_id]
		if player.has("questions"):
			for question in player.questions:
				all_questions_data.append(question)
	return all_questions_data

@rpc("any_peer", "call_local")
func submit_player_score(player_name: String, score: int):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:  # 로컬 호스트인 경우
		sender_id = 1
	
	print("점수 수신: ", player_name, " - ", score, "점")
	
	if sender_id in connected_players:
		connected_players[sender_id]["score"] = score
		connected_players[sender_id]["name"] = player_name
		score_updated.emit(sender_id, score)
		
		# 서버인 경우 모든 클라이언트에게 점수 데이터 동기화
		if is_server:
			broadcast_all_scores()

func broadcast_all_scores():
	var scores_data = {}
	for player_id in connected_players:
		var player = connected_players[player_id]
		if player.has("name"):
			scores_data[player.name] = player.get("score", 0)
	
	print("모든 플레이어 점수 브로드캐스트: ", scores_data)
	rpc("sync_all_scores", scores_data)

@rpc("authority", "call_local")
func sync_all_scores(scores_data: Dictionary):
	print("점수 데이터 동기화 수신: ", scores_data)
	all_scores_received.emit(scores_data)

@rpc("authority", "call_local")
func start_game_phase(phase: String, data: Dictionary = {}):
	game_state_changed.emit({"phase": phase, "data": data})

@rpc("authority", "call_local")
func sync_game_data(game_data: Dictionary):
	# 게임 데이터 동기화 (질문, 점수 등)
	game_state_changed.emit({"phase": "sync", "data": game_data})

func get_local_ip():
	var ip_addresses = IP.get_local_addresses()
	for ip in ip_addresses:
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"

func _on_player_connected(id):
	print("플레이어 연결됨: ", id)
	if is_server:
		# 서버가 새 클라이언트에게 현재 연결된 모든 플레이어 정보 전송
		rpc_id(id, "sync_connected_players", connected_players)

@rpc("authority")
func sync_connected_players(players: Dictionary):
	connected_players = players
	for player_id in players:
		player_connected.emit(player_id, players[player_id])

func _on_player_disconnected(id):
	print("플레이어 연결 해제됨: ", id)
	if id in connected_players:
		connected_players.erase(id)
	player_disconnected.emit(id)

func disconnect_from_game():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	connected_players.clear()
	player_info = {"name": "", "id": 0}
	is_server = false
