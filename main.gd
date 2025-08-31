extends Control

# 아이스 브레이킹 게임 - 서로 알아가기 퀴즈 (멀티플레이어)
# WiFi를 통해 여러 플레이어가 각자의 컴퓨터에서 참여

enum GameState {
	NETWORK_SETUP,
	WAITING_FOR_PLAYERS,
	INPUT_QNA,
	WAITING_FOR_QUESTIONS,
	PLAYING,
	SHOW_RESULTS
}

var current_state = GameState.NETWORK_SETUP
var players = []
var player_questions = {}  # {player_name: [{question: "", answer: ""}, ...]}
var all_questions = []  # 모든 질문들
var current_question_index = 0
var player_scores = {}  # {player_name: score}
var current_answers = {}  # 현재 질문에 대한 각 플레이어의 답변

# 네트워크 관련
var network_manager
var my_player_name = ""
var is_host = false

# UI 노드들
var ui_container
var title_label
var input_container
var game_container
var result_container
var input_scroll_container
var game_scroll_container
var result_scroll_container

# 반응형 UI를 위한 기본 화면 크기
var base_screen_size = Vector2(1280, 720)
var current_scale_factor = 1.0

func _ready():
	setup_network()
	setup_ui()
	start_game()
	
	# 화면 크기 변경 감지
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()  # 초기 크기 계산

func _on_viewport_size_changed():
	var viewport_size = get_viewport().get_visible_rect().size
	var scale_x = viewport_size.x / base_screen_size.x
	var scale_y = viewport_size.y / base_screen_size.y
	current_scale_factor = min(scale_x, scale_y)
	
	# 최소/최대 스케일 제한
	current_scale_factor = clamp(current_scale_factor, 0.5, 3.0)
	
	print("화면 크기 변경됨: ", viewport_size, " 스케일 팩터: ", current_scale_factor)
	
	# 기존 UI 요소들의 폰트 크기 업데이트
	update_all_font_sizes()

func get_scaled_font_size(base_size: int) -> int:
	return int(base_size * current_scale_factor)

func update_all_font_sizes():
	# 제목 라벨 업데이트
	if title_label:
		title_label.add_theme_font_size_override("font_size", get_scaled_font_size(32))
	
	# 모든 컨테이너의 라벨들과 버튼들을 재귀적으로 업데이트
	update_container_font_sizes(input_container)
	update_container_font_sizes(game_container)
	update_container_font_sizes(result_container)

func update_container_font_sizes(container: Node):
	if not container:
		return
		
	for child in container.get_children():
		if child is Label:
			# 라벨의 현재 폰트 크기를 기준으로 스케일링
			var current_size = child.get_theme_font_size("font_size")
			if current_size > 0:
				# 기본 크기를 추정하여 스케일링
				var base_size = current_size / current_scale_factor if current_scale_factor > 0 else current_size
				child.add_theme_font_size_override("font_size", get_scaled_font_size(int(base_size)))
		elif child is Button:
			# 버튼의 폰트 크기도 업데이트
			var current_size = child.get_theme_font_size("font_size")
			if current_size > 0:
				var base_size = current_size / current_scale_factor if current_scale_factor > 0 else current_size
				child.add_theme_font_size_override("font_size", get_scaled_font_size(int(base_size)))
		
		# 재귀적으로 자식 노드들도 처리
		if child.get_child_count() > 0:
			update_container_font_sizes(child)

func setup_network():
	# 네트워크 매니저 로드
	network_manager = preload("res://network_manager.gd").new()
	add_child(network_manager)
	
	# 시그널 연결
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.question_received.connect(_on_question_received)
	network_manager.all_questions_ready.connect(_on_all_questions_ready)
	network_manager.game_state_changed.connect(_on_game_state_changed)
	network_manager.score_updated.connect(_on_score_updated)
	network_manager.all_scores_received.connect(_on_all_scores_received)

func setup_ui():
	# 메인 UI 컨테이너
	ui_container = VBoxContainer.new()
	ui_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_container.add_theme_constant_override("separation", 20)
	add_child(ui_container)
	
	# 제목
	title_label = Label.new()
	title_label.text = "🎮 서로 알아가기 아이스 브레이킹 게임 🎮"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", get_scaled_font_size(32))
	ui_container.add_child(title_label)
	
	# 스크롤 컨테이너 추가
	input_scroll_container = ScrollContainer.new()
	input_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_container.add_child(input_scroll_container)
	
	# 입력 컨테이너 (스크롤 컨테이너 안에)
	input_container = VBoxContainer.new()
	input_container.add_theme_constant_override("separation", 15)
	input_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 여백 추가
	input_container.add_theme_constant_override("margin_left", 20)
	input_container.add_theme_constant_override("margin_right", 20)
	input_container.add_theme_constant_override("margin_top", 10)
	input_container.add_theme_constant_override("margin_bottom", 20)
	input_scroll_container.add_child(input_container)
	
	# 게임용 스크롤 컨테이너
	game_scroll_container = ScrollContainer.new()
	game_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_scroll_container.visible = false
	ui_container.add_child(game_scroll_container)
	
	# 게임 컨테이너
	game_container = VBoxContainer.new()
	game_container.add_theme_constant_override("separation", 15)
	game_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_scroll_container.add_child(game_container)
	
	# 결과용 스크롤 컨테이너
	result_scroll_container = ScrollContainer.new()
	result_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_scroll_container.visible = false
	ui_container.add_child(result_scroll_container)
	
	# 결과 컨테이너
	result_container = VBoxContainer.new()
	result_container.add_theme_constant_override("separation", 10)
	result_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_scroll_container.add_child(result_container)

func start_game():
	setup_network_selection()

func setup_network_selection():
	current_state = GameState.NETWORK_SETUP
	clear_container(input_container)
	
	var instruction = Label.new()
	instruction.text = "네트워크 게임 설정"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", get_scaled_font_size(24))
	input_container.add_child(instruction)
	
	var info_label = Label.new()
	info_label.text = "같은 WiFi에 연결된 사람들과 게임하세요!"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_container.add_child(info_label)
	
	input_container.add_child(HSeparator.new())
	
	# 이름 입력
	var name_label = Label.new()
	name_label.text = "당신의 이름을 입력하세요:"
	input_container.add_child(name_label)
	
	var name_input = LineEdit.new()
	name_input.placeholder_text = "이름을 입력하세요"
	name_input.custom_minimum_size.x = 300
	input_container.add_child(name_input)
	
	input_container.add_child(HSeparator.new())
	
	# 호스트 버튼
	var host_button = Button.new()
	host_button.text = "🏠 게임 호스트하기 (방 만들기)"
	host_button.custom_minimum_size.y = 50
	host_button.pressed.connect(_on_host_game.bind(name_input))
	input_container.add_child(host_button)
	
	# 참가 섹션
	var join_label = Label.new()
	join_label.text = "또는 기존 게임에 참가:"
	input_container.add_child(join_label)
	
	var ip_input = LineEdit.new()
	ip_input.placeholder_text = "호스트 IP 주소 (예: 192.168.1.100)"
	ip_input.custom_minimum_size.x = 300
	input_container.add_child(ip_input)
	
	var join_button = Button.new()
	join_button.text = "🔗 게임 참가하기"
	join_button.custom_minimum_size.y = 50
	join_button.pressed.connect(_on_join_game.bind(name_input, ip_input))
	input_container.add_child(join_button)

# 네트워크 콜백 함수들
func _on_host_game(name_input):
	var player_name = name_input.text.strip_edges()
	if player_name == "":
		show_message("이름을 입력해주세요!")
		return
	
	my_player_name = player_name
	network_manager.set_player_name(player_name)
	
	if network_manager.create_server():
		is_host = true
		setup_waiting_room()
	else:
		show_message("서버 생성에 실패했습니다!")

func _on_join_game(name_input, ip_input):
	var player_name = name_input.text.strip_edges()
	var host_ip = ip_input.text.strip_edges()
	
	if player_name == "":
		show_message("이름을 입력해주세요!")
		return
	if host_ip == "":
		show_message("호스트 IP를 입력해주세요!")
		return
	
	my_player_name = player_name
	network_manager.set_player_name(player_name)
	
	if network_manager.join_server(host_ip):
		is_host = false
		# 접속 후 약간 대기한 후 플레이어 정보 전송
		await get_tree().create_timer(0.5).timeout
		network_manager.set_player_name(player_name)
		setup_waiting_room()
	else:
		show_message("서버 연결에 실패했습니다!")

func setup_waiting_room():
	current_state = GameState.WAITING_FOR_PLAYERS
	clear_container(input_container)
	
	var title = Label.new()
	if is_host:
		title.text = "🏠 게임 방 (호스트)"
		var ip_info = Label.new()
		ip_info.text = "다른 플레이어들에게 알려줄 IP: %s" % network_manager.get_local_ip()
		ip_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ip_info.add_theme_font_size_override("font_size", get_scaled_font_size(16))
		ip_info.add_theme_color_override("font_color", Color.ORANGE)
		input_container.add_child(title)
		input_container.add_child(ip_info)
	else:
		title.text = "🔗 게임 방 (참가자)"
		input_container.add_child(title)
	
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", get_scaled_font_size(24))
	
	input_container.add_child(HSeparator.new())
	
	var players_label = Label.new()
	players_label.text = "연결된 플레이어들:"
	players_label.add_theme_font_size_override("font_size", get_scaled_font_size(18))
	input_container.add_child(players_label)
	
	# 플레이어 목록 컨테이너 (동적으로 업데이트됨)
	var players_container = VBoxContainer.new()
	players_container.name = "PlayersContainer"
	input_container.add_child(players_container)
	
	# 현재 연결된 플레이어 표시
	update_player_list()
	
	if is_host:
		input_container.add_child(HSeparator.new())
		var start_button = Button.new()
		start_button.text = "🎮 게임 시작하기 (최소 2명)"
		start_button.custom_minimum_size.y = 50
		start_button.pressed.connect(_on_start_question_phase)
		input_container.add_child(start_button)

func update_player_list():
	var players_container = input_container.get_node("PlayersContainer")
	if not players_container:
		return
	
	# 기존 플레이어 목록 지우기
	for child in players_container.get_children():
		child.queue_free()
	
	# 새 플레이어 목록 추가
	var player_count = 0
	for player_id in network_manager.connected_players:
		var player_info = network_manager.connected_players[player_id]
		var player_label = Label.new()
		if player_info.name == my_player_name:
			player_label.text = "👤 %s (나)" % player_info.name
		else:
			player_label.text = "👤 %s" % player_info.name
		players_container.add_child(player_label)
		player_count += 1
	
	# 플레이어 수 표시
	var count_label = Label.new()
	count_label.text = "총 %d명 연결됨" % player_count
	count_label.add_theme_color_override("font_color", Color.ORANGE)
	players_container.add_child(count_label)
	
	print("플레이어 목록 업데이트: %d명" % player_count)

func _on_player_connected(_id, player_info):
	print("플레이어 연결: ", player_info.name)
	update_player_list()

func _on_player_disconnected(_id):
	print("플레이어 연결 해제: ", _id)
	update_player_list()

func _on_start_question_phase():
	# 호스트 자신의 정보가 누락되었을 수 있으므로 다시 확인
	if is_host and my_player_name != "":
		network_manager.player_info.name = my_player_name
		network_manager.connected_players[1] = network_manager.player_info.duplicate()
	
	var player_count = network_manager.connected_players.size()
	print("현재 연결된 플레이어 수: ", player_count)
	print("연결된 플레이어들: ", network_manager.connected_players.keys())
	
	if player_count < 2:
		show_message("최소 2명의 플레이어가 필요합니다! (현재: %d명)" % player_count)
		return
	
	# 모든 클라이언트에게 질문 입력 단계 시작 알림
	network_manager.rpc("start_game_phase", "INPUT_QNA")
	setup_question_input()

func _on_game_state_changed(state_data):
	var phase = state_data.phase
	var data = state_data.get("data", {})
	
	match phase:
		"INPUT_QNA":
			setup_question_input()
		"START_QUIZ":
			print("퀴즈 시작 신호를 받았습니다!")
			# 클라이언트인 경우 서버에서 보낸 질문 데이터를 사용
			if not is_host and data.has("all_questions"):
				print("서버에서 받은 질문 데이터로 퀴즈를 시작합니다.")
				sync_questions_from_server(data.all_questions)
			start_quiz_round()
		"sync":
			# 게임 데이터 동기화
			pass

func sync_questions_from_server(all_questions_data):
	# 서버에서 받은 모든 질문 데이터를 로컬에 동기화
	print("서버에서 %d개의 질문을 받았습니다." % all_questions_data.size())
	
	# 플레이어별로 질문 분류
	player_questions.clear()
	for question_data in all_questions_data:
		var player_name = question_data.player
		if not player_questions.has(player_name):
			player_questions[player_name] = []
		player_questions[player_name].append(question_data)
	
	print("동기화된 플레이어 질문들: ", player_questions.keys())

func _on_question_received(player_id, questions):
	# 질문 수신 처리
	var player_name = network_manager.connected_players[player_id].name
	player_questions[player_name] = questions
	print("질문 수신: ", player_name, " - ", questions.size(), "개")

func _on_all_questions_ready():
	print("모든 질문이 준비되었습니다!")
	# 네트워크 매니저가 자동으로 START_QUIZ 신호를 보내므로
	# 호스트도 다른 플레이어와 동일하게 신호를 기다립니다.
	print("퀴즈 시작 신호를 기다리는 중...")

func setup_question_input():
	current_state = GameState.INPUT_QNA
	clear_container(input_container)
	
	var instruction = Label.new()
	instruction.text = "%s님, 자신에 대한 질문과 답변을 3개 입력해주세요!" % my_player_name
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", get_scaled_font_size(18))
	input_container.add_child(instruction)
	
	var sub_instruction = Label.new()
	sub_instruction.text = "다른 사람들이 추측하기 재미있는 질문을 만들어보세요!"
	sub_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_instruction.add_theme_color_override("font_color", Color.GRAY)
	input_container.add_child(sub_instruction)
	
	# 구분선 추가
	input_container.add_child(HSeparator.new())
	
	var player_section = VBoxContainer.new()
	player_section.add_theme_constant_override("separation", 8)
	
	var qna_inputs = []
	for i in range(3):
		var qna_container = VBoxContainer.new()
		qna_container.add_theme_constant_override("separation", 5)
		
		var q_label = Label.new()
		q_label.text = "질문 %d:" % (i + 1)
		q_label.add_theme_font_size_override("font_size", get_scaled_font_size(16))
		qna_container.add_child(q_label)
		
		var question_input = LineEdit.new()
		question_input.placeholder_text = "예: 내가 가장 좋아하는 음식은?"
		question_input.custom_minimum_size.x = 500
		question_input.custom_minimum_size.y = 35
		qna_container.add_child(question_input)
		
		var a_label = Label.new()
		a_label.text = "답변:"
		a_label.add_theme_font_size_override("font_size", get_scaled_font_size(16))
		qna_container.add_child(a_label)
		
		var answer_input = LineEdit.new()
		answer_input.placeholder_text = "예: 피자"
		answer_input.custom_minimum_size.x = 500
		answer_input.custom_minimum_size.y = 35
		qna_container.add_child(answer_input)
		
		qna_inputs.append({"question": question_input, "answer": answer_input})
		
		# 질문 간 구분선
		if i < 2:  # 마지막 질문 후에는 구분선 없음
			var separator = HSeparator.new()
			separator.add_theme_constant_override("separation", 10)
			qna_container.add_child(separator)
		
		player_section.add_child(qna_container)
	
	input_container.add_child(player_section)
	
	# 제출 버튼
	var submit_button = Button.new()
	submit_button.text = "📝 질문 제출하기"
	submit_button.custom_minimum_size.x = 250
	submit_button.custom_minimum_size.y = 50
	submit_button.add_theme_font_size_override("font_size", get_scaled_font_size(18))
	submit_button.pressed.connect(_on_submit_questions.bind(qna_inputs))
	input_container.add_child(submit_button)
	
	# 대기 상태 표시
	var status_label = Label.new()
	status_label.text = ""
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_container.add_child(status_label)

func _on_submit_questions(qna_inputs):
	var questions = []
	
	for qna_input in qna_inputs:
		var question = qna_input["question"].text.strip_edges()
		var answer = qna_input["answer"].text.strip_edges()
		
		if question != "" and answer != "":
			questions.append({
				"question": question,
				"answer": answer,
				"player": my_player_name
			})
	
	if questions.size() < 3:
		show_message("3개의 질문을 모두 입력해주세요!")
		return
	
	print("%s가 질문 %d개를 제출합니다." % [my_player_name, questions.size()])
	
	# 네트워크로 질문 전송
	network_manager.rpc("submit_questions", questions)
	
	# UI 업데이트 - 제출 완료 상태
	var status_label = input_container.get_node("StatusLabel")
	if status_label:
		if is_host:
			status_label.text = "✅ 질문이 제출되었습니다! 다른 플레이어를 기다리는 중...\n모든 플레이어가 제출하면 자동으로 퀴즈가 시작됩니다."
		else:
			status_label.text = "✅ 질문이 제출되었습니다! 호스트와 다른 플레이어를 기다리는 중...\n모든 플레이어가 제출하면 자동으로 퀴즈가 시작됩니다."
		status_label.add_theme_color_override("font_color", Color.GREEN)
	
	# 입력 필드 비활성화
	for qna_input in qna_inputs:
		qna_input["question"].editable = false
		qna_input["answer"].editable = false

func start_quiz_round():
	print("퀴즈 라운드를 시작합니다!")
	print("수집된 플레이어 질문들: ", player_questions.keys())
	
	current_state = GameState.PLAYING
	input_scroll_container.visible = false
	game_scroll_container.visible = true
	
	# 모든 질문 수집
	all_questions.clear()
	for player_name in player_questions:
		for question_data in player_questions[player_name]:
			all_questions.append(question_data)
			
	print("총 %d개의 질문이 수집되었습니다." % all_questions.size())
	
	# 질문 순서 섞기
	all_questions.shuffle()
	current_question_index = 0
	
	# 플레이어 점수 초기화
	for player_id in network_manager.connected_players:
		var player_name = network_manager.connected_players[player_id].name
		player_scores[player_name] = 0
	
	show_current_question()

func show_current_question():
	clear_container(game_container)
	
	if current_question_index >= all_questions.size():
		show_final_results()
		return
	
	var current_qna = all_questions[current_question_index]
	
	# 질문 표시
	var question_label = Label.new()
	question_label.text = "질문 %d/%d: %s" % [current_question_index + 1, all_questions.size(), current_qna["question"]]
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.add_theme_font_size_override("font_size", get_scaled_font_size(24))
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_container.add_child(question_label)
	
	# 답변 표시
	var answer_label = Label.new()
	answer_label.text = "답변: %s" % current_qna["answer"]
	answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	answer_label.add_theme_font_size_override("font_size", get_scaled_font_size(20))
	answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_container.add_child(answer_label)
	
	var instruction = Label.new()
	instruction.text = "이 답변을 한 사람은 누구일까요?"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_container.add_child(instruction)
	
	# 내 추측 입력 (자신만)
	var my_section = HBoxContainer.new()
	var my_label = Label.new()
	my_label.text = "%s의 추측: " % my_player_name
	my_label.custom_minimum_size.x = 150
	my_section.add_child(my_label)
	
	var option_button = OptionButton.new()
	option_button.add_item("선택하세요...")
	for player_id in network_manager.connected_players:
		var player_name = network_manager.connected_players[player_id].name
		option_button.add_item(player_name)
	
	my_section.add_child(option_button)
	game_container.add_child(my_section)
	
	# 제출 버튼
	var submit_button = Button.new()
	submit_button.text = "답변 제출"
	submit_button.pressed.connect(_on_my_answer_submitted.bind(option_button, current_qna))
	game_container.add_child(submit_button)

func _on_my_answer_submitted(option_button, correct_qna):
	var selected_index = option_button.selected
	if selected_index <= 0:
		show_message("답변을 선택해주세요!")
		return
	
	# 선택된 플레이어 찾기
	var player_names = []
	for player_id in network_manager.connected_players:
		player_names.append(network_manager.connected_players[player_id].name)
	
	var selected_player = player_names[selected_index - 1]
	
	# 점수 계산
	var correct_player = correct_qna["player"]
	if selected_player == correct_player:
		player_scores[my_player_name] += 1
	
	# 결과 표시
	show_round_results(correct_qna, selected_player)

func show_round_results(correct_qna, my_guess):
	clear_container(game_container)
	
	var correct_player = correct_qna["player"]
	
	# 정답 공개
	var result_label = Label.new()
	result_label.text = "정답: %s" % correct_player
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", get_scaled_font_size(28))
	game_container.add_child(result_label)
	
	# 내 답변 결과
	var my_result = Label.new()
	if my_guess == correct_player:
		my_result.text = "✅ %s: %s (정답!)" % [my_player_name, my_guess]
		my_result.add_theme_color_override("font_color", Color.GREEN)
	else:
		my_result.text = "❌ %s: %s" % [my_player_name, my_guess]
		my_result.add_theme_color_override("font_color", Color.RED)
	
	my_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_container.add_child(my_result)
	
	# 현재 점수 표시 및 네트워크로 전송
	var score_label = Label.new()
	score_label.text = "\n내 점수: %d점" % player_scores[my_player_name]
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_container.add_child(score_label)
	
	# 점수를 네트워크로 전송
	network_manager.rpc("submit_player_score", my_player_name, player_scores[my_player_name])
	
	# 다음 버튼
	var next_button = Button.new()
	if current_question_index + 1 < all_questions.size():
		next_button.text = "다음 질문"
		next_button.pressed.connect(_on_next_question)
	else:
		next_button.text = "최종 결과 보기"
		next_button.pressed.connect(show_final_results)
	
	game_container.add_child(next_button)

func _on_next_question():
	current_question_index += 1
	show_current_question()

func show_final_results():
	current_state = GameState.SHOW_RESULTS
	game_scroll_container.visible = false
	result_scroll_container.visible = true
	
	# 최종 점수를 네트워크로 전송
	print("최종 점수 전송: ", my_player_name, " - ", player_scores[my_player_name], "점")
	network_manager.rpc("submit_player_score", my_player_name, player_scores[my_player_name])
	
	setup_results_ui()
	
	# 점수 동기화를 위한 대기 및 요청
	await get_tree().create_timer(1.5).timeout
	print("점수 동기화 요청...")
	
	# 호스트든 클라이언트든 점수 동기화 요청
	if is_host:
		print("호스트가 점수 브로드캐스트를 시작합니다.")
		network_manager.broadcast_all_scores()
	else:
		print("클라이언트가 호스트에게 점수 동기화를 요청합니다.")
		network_manager.rpc_id(1, "request_score_broadcast")
	
	# 추가로 2초 후에도 다시 시도 (대비책)
	await get_tree().create_timer(2.0).timeout
	if is_host:
		network_manager.broadcast_all_scores()

func setup_results_ui():
	clear_container(result_container)
	
	# 최종 결과 제목
	var title = Label.new()
	title.text = "🏆 게임 종료! 최종 결과 🏆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", get_scaled_font_size(32))
	result_container.add_child(title)
	
	# 내 최종 점수
	var my_score_label = Label.new()
	my_score_label.text = "내 최종 점수: %d점" % player_scores[my_player_name]
	my_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_score_label.add_theme_font_size_override("font_size", get_scaled_font_size(24))
	my_score_label.add_theme_color_override("font_color", Color.BLUE)
	result_container.add_child(my_score_label)
	
	result_container.add_child(HSeparator.new())
	
	# 모든 플레이어 점수 섹션
	var all_scores_title = Label.new()
	all_scores_title.text = "📊 모든 플레이어 점수"
	all_scores_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	all_scores_title.add_theme_font_size_override("font_size", get_scaled_font_size(20))
	result_container.add_child(all_scores_title)
	
	# 점수 목록 컨테이너 (동적으로 업데이트됨)
	var scores_container = VBoxContainer.new()
	scores_container.name = "ScoresContainer"
	scores_container.add_theme_constant_override("separation", 5)
	result_container.add_child(scores_container)
	
	# 로딩 메시지
	var loading_label = Label.new()
	loading_label.text = "⏳ 다른 플레이어들의 점수를 받아오는 중..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_color_override("font_color", Color.GRAY)
	scores_container.add_child(loading_label)
	
	result_container.add_child(HSeparator.new())
	
	# 점수 새로고침 버튼
	var refresh_button = Button.new()
	refresh_button.text = "🔄 점수 새로고침"
	refresh_button.custom_minimum_size.y = 40
	refresh_button.pressed.connect(_on_refresh_scores)
	result_container.add_child(refresh_button)
	
	# 다시 시작 버튼
	var restart_button = Button.new()
	restart_button.text = "🆕 새 게임하기"
	restart_button.custom_minimum_size.y = 50
	restart_button.pressed.connect(restart_game)
	result_container.add_child(restart_button)

func _on_refresh_scores():
	print("수동 점수 새로고침 요청")
	if is_host:
		print("호스트가 점수를 다시 브로드캐스트합니다.")
		network_manager.broadcast_all_scores()
	else:
		print("클라이언트가 호스트에게 점수 새로고침을 요청합니다.")
		network_manager.rpc_id(1, "request_score_broadcast")

# 점수 관련 콜백 함수들
func _on_score_updated(_player_id, _score):
	# 개별 점수 업데이트시 호스트가 자동으로 브로드캐스트
	if is_host and current_state == GameState.SHOW_RESULTS:
		print("점수 업데이트 감지, 자동 브로드캐스트")
		await get_tree().create_timer(0.5).timeout  # 약간의 지연
		network_manager.broadcast_all_scores()

func _on_all_scores_received(scores_data):
	print("모든 플레이어 점수 수신: ", scores_data)
	update_all_scores_display(scores_data)

func update_all_scores_display(scores_data: Dictionary):
	var scores_container = result_container.get_node("ScoresContainer")
	if not scores_container:
		return
	
	# 기존 점수 목록 지우기
	for child in scores_container.get_children():
		child.queue_free()
	
	if scores_data.is_empty():
		var no_data_label = Label.new()
		no_data_label.text = "❌ 점수 데이터가 없습니다. '점수 새로고침' 버튼을 눌러보세요."
		no_data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_data_label.add_theme_color_override("font_color", Color.RED)
		scores_container.add_child(no_data_label)
		return
	
	# 점수 순으로 정렬
	var sorted_scores = []
	for player_name in scores_data:
		sorted_scores.append({"name": player_name, "score": scores_data[player_name]})
	
	sorted_scores.sort_custom(func(a, b): return a.score > b.score)
	
	# 순위 표시
	for i in range(sorted_scores.size()):
		var player_data = sorted_scores[i]
		var rank_text = ""
		var rank_color = Color.WHITE
		
		match i:
			0: 
				rank_text = "🥇 1위: %s (%d점)" % [player_data.name, player_data.score]
				rank_color = Color.GOLD
			1: 
				rank_text = "🥈 2위: %s (%d점)" % [player_data.name, player_data.score]
				rank_color = Color.SILVER
			2: 
				rank_text = "🥉 3위: %s (%d점)" % [player_data.name, player_data.score]
				rank_color = Color("#CD7F32")  # Bronze color
			_: 
				rank_text = "%d위: %s (%d점)" % [i + 1, player_data.name, player_data.score]
				rank_color = Color.WHITE
		
		var rank_label = Label.new()
		rank_label.text = rank_text
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.add_theme_font_size_override("font_size", get_scaled_font_size(18))
		rank_label.add_theme_color_override("font_color", rank_color)
		
		# 자신의 점수는 배경색으로 강조
		if player_data.name == my_player_name:
			rank_label.add_theme_color_override("font_color", Color.CYAN)
			rank_label.text += " ⭐"
		
		scores_container.add_child(rank_label)

func restart_game():
	# 네트워크 연결 해제
	network_manager.disconnect_from_game()
	
	# 모든 데이터 초기화
	players.clear()
	player_questions.clear()
	all_questions.clear()
	player_scores.clear()
	current_answers.clear()
	current_question_index = 0
	my_player_name = ""
	is_host = false
	
	# UI 초기화
	result_scroll_container.visible = false
	input_scroll_container.visible = true
	
	start_game()

func clear_container(container):
	for child in container.get_children():
		child.queue_free()

func show_message(message):
	# 실제 UI 다이얼로그로 메시지 표시
	print(message)  # 디버그용 로그는 유지
	
	# AcceptDialog를 사용한 메시지 팝업
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "알림"
	dialog.min_size = Vector2(400, 200)
	
	# 다이얼로그를 현재 씬에 추가
	add_child(dialog)
	
	# 팝업 표시
	dialog.popup_centered()
	
	# 다이얼로그가 닫힐 때 자동으로 제거
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.close_requested.connect(func(): dialog.queue_free())
