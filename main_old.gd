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

func _ready():
	setup_network()
	setup_ui()
	start_game()

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
	title_label.add_theme_font_size_override("font_size", 32)
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
	instruction.add_theme_font_size_override("font_size", 24)
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
		ip_info.add_theme_font_size_override("font_size", 16)
		ip_info.add_theme_color_override("font_color", Color.BLUE)
		input_container.add_child(title)
		input_container.add_child(ip_info)
	else:
		title.text = "🔗 게임 방 (참가자)"
		input_container.add_child(title)
	
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	
	input_container.add_child(HSeparator.new())
	
	var players_label = Label.new()
	players_label.text = "연결된 플레이어들:"
	players_label.add_theme_font_size_override("font_size", 18)
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
	for player_id in network_manager.connected_players:
		var player_info = network_manager.connected_players[player_id]
		var player_label = Label.new()
		player_label.text = "👤 %s" % player_info.name
		players_container.add_child(player_label)

func _on_player_connected(id, player_info):
	print("플레이어 연결: ", player_info.name)
	update_player_list()

func _on_player_disconnected(id):
	print("플레이어 연결 해제: ", id)
	update_player_list()

func _on_start_question_phase():
	if network_manager.connected_players.size() < 2:
		show_message("최소 2명의 플레이어가 필요합니다!")
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
		"sync":
			# 게임 데이터 동기화
			pass

func _on_question_received(player_id, questions):
	# 질문 수신 처리
	var player_name = network_manager.connected_players[player_id].name
	player_questions[player_name] = questions
	print("질문 수신: ", player_name, " - ", questions.size(), "개")

func _on_all_questions_ready():
	# 모든 질문이 준비되면 게임 시작
	if is_host:
		start_quiz_round()

func setup_question_input():
	current_state = GameState.INPUT_QNA
	clear_container(input_container)
	
	var instruction = Label.new()
	instruction.text = "%s님, 자신에 대한 질문과 답변을 3개 입력해주세요!" % my_player_name
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 18)
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
		q_label.add_theme_font_size_override("font_size", 16)
		qna_container.add_child(q_label)
		
		var question_input = LineEdit.new()
		question_input.placeholder_text = "예: 내가 가장 좋아하는 음식은?"
		question_input.custom_minimum_size.x = 500
		question_input.custom_minimum_size.y = 35
		qna_container.add_child(question_input)
		
		var a_label = Label.new()
		a_label.text = "답변:"
		a_label.add_theme_font_size_override("font_size", 16)
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
	submit_button.add_theme_font_size_override("font_size", 18)
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
	
	# 네트워크로 질문 전송
	network_manager.rpc("submit_questions", questions)
	
	# UI 업데이트 - 제출 완료 상태
	var status_label = input_container.get_node("StatusLabel")
	if status_label:
		status_label.text = "✅ 질문이 제출되었습니다! 다른 플레이어를 기다리는 중..."
		status_label.add_theme_color_override("font_color", Color.GREEN)
	
	# 입력 필드 비활성화
	for qna_input in qna_inputs:
		qna_input["question"].editable = false
		qna_input["answer"].editable = false

func _on_players_confirmed(player_inputs):
	players.clear()
	for input_field in player_inputs:
		var player_name = input_field.text.strip_edges()
		if player_name != "":
			players.append(player_name)
			player_scores[player_name] = 0
	
	if players.size() < 2:
		show_message("최소 2명의 플레이어가 필요합니다!")
		return
	
	setup_question_input()

func setup_question_input():
	current_state = GameState.INPUT_QNA
	clear_container(input_container)
	
	var instruction = Label.new()
	instruction.text = "각 플레이어는 자신에 대한 질문과 답변을 3개씩 입력해주세요"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 18)
	input_container.add_child(instruction)
	
	# 구분선 추가
	input_container.add_child(HSeparator.new())
	
	for player in players:
		player_questions[player] = []
		
		var player_section = VBoxContainer.new()
		player_section.add_theme_constant_override("separation", 8)
		
		var player_label = Label.new()
		player_label.text = "=== %s의 질문들 ===" % player
		player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_label.add_theme_font_size_override("font_size", 22)
		player_label.add_theme_color_override("font_color", Color.BLUE)
		player_section.add_child(player_label)
		
		var qna_inputs = []
		for i in range(3):
			var qna_container = VBoxContainer.new()
			qna_container.add_theme_constant_override("separation", 5)
			
			var q_label = Label.new()
			q_label.text = "질문 %d:" % (i + 1)
			q_label.add_theme_font_size_override("font_size", 16)
			qna_container.add_child(q_label)
			
			var question_input = LineEdit.new()
			question_input.placeholder_text = "예: 내가 가장 좋아하는 음식은?"
			question_input.custom_minimum_size.x = 500
			question_input.custom_minimum_size.y = 35
			qna_container.add_child(question_input)
			
			var a_label = Label.new()
			a_label.text = "답변:"
			a_label.add_theme_font_size_override("font_size", 16)
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
		
		player_questions[player] = qna_inputs
		input_container.add_child(player_section)
		
		# 플레이어 간 큰 구분선
		var big_separator = HSeparator.new()
		big_separator.add_theme_constant_override("separation", 20)
		input_container.add_child(big_separator)
	
	# 게임 시작 버튼
	var start_button = Button.new()
	start_button.text = "🎮 게임 시작!"
	start_button.custom_minimum_size.x = 250
	start_button.custom_minimum_size.y = 50
	start_button.add_theme_font_size_override("font_size", 18)
	start_button.pressed.connect(_on_start_quiz_game)
	input_container.add_child(start_button)

func _on_start_quiz_game():
	# 질문과 답변 수집
	all_questions.clear()
	
	for player in players:
		var qna_inputs = player_questions[player]
		var player_qnas = []
		
		for qna_input in qna_inputs:
			var question = qna_input["question"].text.strip_edges()
			var answer = qna_input["answer"].text.strip_edges()
			
			if question != "" and answer != "":
				var qna_data = {
					"question": question,
					"answer": answer,
					"player": player
				}
				all_questions.append(qna_data)
				player_qnas.append(qna_data)
		
		player_questions[player] = player_qnas
	
	if all_questions.size() < 3:
		show_message("게임을 시작하려면 최소 3개의 질문이 필요합니다!")
		return
	
	# 질문 순서 섞기
	all_questions.shuffle()
	current_question_index = 0
	
	start_quiz_round()

func start_quiz_round():
	current_state = GameState.PLAYING
	input_scroll_container.visible = false
	game_scroll_container.visible = true
	
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
	question_label.add_theme_font_size_override("font_size", 24)
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_container.add_child(question_label)
	
	# 답변 표시
	var answer_label = Label.new()
	answer_label.text = "답변: %s" % current_qna["answer"]
	answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	answer_label.add_theme_font_size_override("font_size", 20)
	answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_container.add_child(answer_label)
	
	var instruction = Label.new()
	instruction.text = "이 답변을 한 사람은 누구일까요?"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_container.add_child(instruction)
	
	# 각 플레이어의 추측 입력
	current_answers.clear()
	var answer_inputs = {}
	
	for player in players:
		var player_section = HBoxContainer.new()
		
		var player_label = Label.new()
		player_label.text = "%s의 추측: " % player
		player_label.custom_minimum_size.x = 150
		player_section.add_child(player_label)
		
		var option_button = OptionButton.new()
		option_button.add_item("선택하세요...")
		for other_player in players:
			option_button.add_item(other_player)
		
		answer_inputs[player] = option_button
		player_section.add_child(option_button)
		game_container.add_child(player_section)
	
	# 제출 버튼
	var submit_button = Button.new()
	submit_button.text = "답변 제출"
	submit_button.pressed.connect(_on_answers_submitted.bind(answer_inputs, current_qna))
	game_container.add_child(submit_button)

func _on_answers_submitted(answer_inputs, correct_qna):
	# 답변 수집
	current_answers.clear()
	for player in players:
		var selected_index = answer_inputs[player].selected
		if selected_index > 0:  # 0은 "선택하세요..."
			var selected_player = players[selected_index - 1]
			current_answers[player] = selected_player
	
	show_round_results(correct_qna)

func show_round_results(correct_qna):
	clear_container(game_container)
	
	var correct_player = correct_qna["player"]
	
	# 정답 공개
	var result_label = Label.new()
	result_label.text = "정답: %s" % correct_player
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 28)
	game_container.add_child(result_label)
	
	# 각 플레이어의 답변과 결과
	var results_container = VBoxContainer.new()
	for player in players:
		var result_text = "%s: " % player
		if player in current_answers:
			var guessed_player = current_answers[player]
			if guessed_player == correct_player:
				result_text += "✅ %s (정답!)" % guessed_player
				player_scores[player] += 1
			else:
				result_text += "❌ %s" % guessed_player
		else:
			result_text += "답변 안함"
		
		var result_item = Label.new()
		result_item.text = result_text
		results_container.add_child(result_item)
	
	game_container.add_child(results_container)
	
	# 현재 점수 표시
	var score_label = Label.new()
	score_label.text = "\n현재 점수:"
	for player in players:
		score_label.text += "\n%s: %d점" % [player, player_scores[player]]
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_container.add_child(score_label)
	
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
	
	clear_container(result_container)
	
	# 최종 결과 제목
	var title = Label.new()
	title.text = "🏆 게임 종료! 최종 결과 🏆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	result_container.add_child(title)
	
	# 점수 순으로 정렬
	var sorted_players = players.duplicate()
	sorted_players.sort_custom(func(a, b): return player_scores[a] > player_scores[b])
	
	# 순위 표시
	var rank_container = VBoxContainer.new()
	for i in range(sorted_players.size()):
		var player = sorted_players[i]
		var rank_text = ""
		
		match i:
			0: rank_text = "🥇 1위: %s (%d점)" % [player, player_scores[player]]
			1: rank_text = "🥈 2위: %s (%d점)" % [player, player_scores[player]]
			2: rank_text = "🥉 3위: %s (%d점)" % [player, player_scores[player]]
			_: rank_text = "%d위: %s (%d점)" % [i + 1, player, player_scores[player]]
		
		var rank_label = Label.new()
		rank_label.text = rank_text
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.add_theme_font_size_override("font_size", 20)
		rank_container.add_child(rank_label)
	
	result_container.add_child(rank_container)
	
	# 다시 시작 버튼
	var restart_button = Button.new()
	restart_button.text = "🔄 다시 게임하기"
	restart_button.pressed.connect(restart_game)
	result_container.add_child(restart_button)

func restart_game():
	# 모든 데이터 초기화
	players.clear()
	player_questions.clear()
	all_questions.clear()
	player_scores.clear()
	current_answers.clear()
	current_question_index = 0
	
	# UI 초기화
	result_scroll_container.visible = false
	input_scroll_container.visible = true
	
	start_game()

func clear_container(container):
	for child in container.get_children():
		child.queue_free()

func show_message(message):
	# 간단한 메시지 표시 (실제로는 더 정교한 UI가 필요)
	print(message)
