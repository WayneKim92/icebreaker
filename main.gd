extends Control

# 아이스 브레이킹 게임 - 서로 알아가기 퀴즈
# 5명의 플레이어가 서로에 대해 알아가는 게임

enum GameState {
	SETUP_PLAYERS,
	INPUT_QNA,
	PLAYING,
	SHOW_RESULTS
}

var current_state = GameState.SETUP_PLAYERS
var players = []
var player_questions = {}  # {player_name: [{question: "", answer: ""}, ...]}
var all_questions = []  # 모든 질문들
var current_question_index = 0
var player_scores = {}  # {player_name: score}
var current_answers = {}  # 현재 질문에 대한 각 플레이어의 답변

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
	setup_ui()
	start_game()

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
	setup_player_input()

func setup_player_input():
	current_state = GameState.SETUP_PLAYERS
	clear_container(input_container)
	
	var instruction = Label.new()
	instruction.text = "5명의 플레이어 이름을 입력해주세요:"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_container.add_child(instruction)
	
	# 플레이어 이름 입력 필드들
	var player_inputs = []
	for i in range(5):
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = "플레이어 %d: " % (i + 1)
		label.custom_minimum_size.x = 100
		
		var line_edit = LineEdit.new()
		line_edit.placeholder_text = "이름을 입력하세요"
		line_edit.custom_minimum_size.x = 200
		player_inputs.append(line_edit)
		
		hbox.add_child(label)
		hbox.add_child(line_edit)
		input_container.add_child(hbox)
	
	# 다음 버튼
	var next_button = Button.new()
	next_button.text = "다음 단계로"
	next_button.custom_minimum_size.x = 200
	next_button.pressed.connect(_on_players_confirmed.bind(player_inputs))
	input_container.add_child(next_button)

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
