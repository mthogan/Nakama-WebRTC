extends Node

onready var socket = NClient.socket
onready var channel : NakamaRTAPI.Channel
onready var client = NClient.client
onready var dialog = $MatchmakeDialog
onready var user_list = $Main/UserList
onready var chat_main = $Main/VBoxContainer/ChatLobby
onready var top_bar = $Main/VBoxContainer/VBoxContainer/TopBar
onready var match_list = $Main/VBoxContainer/VBoxContainer/MatchList
onready var chat_lobby = $Lobby/VBoxContainer/HBoxContainer2/ChatMatch
onready var player_list = $Lobby/VBoxContainer/HBoxContainer2/PlayerList
var my_account
var connected_users = {}
var available_matches = {}
var matchmaker_ticket : NakamaRTAPI.MatchmakerTicket

func _ready():
	socket.connect("connected", self, "_on_socket_connected")
#	socket.connect("closed", self, "_on_closed")
	socket.connect("received_channel_presence", self, "_on_channel_presence_received")
	socket.connect("received_channel_message", self, "_on_channel_message_received")
	socket.connect("received_match_presence", self, "_on_match_presence_received")
	socket.connect("received_matchmaker_matched", self, "_on_matchmaker_matched")
	socket.connect("received_stream_presence", self, "_on_stream_presence_received")
	socket.connect("received_stream_state", self, "_on_stream_state_received")
	dialog.get_close_button().connect("pressed", self, "_on_matchmake_dialog_closed")
	MatchState.connect("game_start", self, "on_game_start")
	chat_main.edit.grab_focus()


func _on_socket_connected():
	#Fetch account info
	my_account = yield(NClient._get_account(), "completed")
	join_stream(my_account.user)
	MatchState.my_user_id = my_account.user.id
	#Join lobby chat channel
	var roomname = "Public"
	var persistence = false
	var hidden = false
	var type = NakamaSocket.ChannelType.Room
	yield(join_chat_channel(roomname, type, persistence, hidden), "completed")
	for p in channel.presences:
#		print("[init channel here %s]"%p)
		connected_users[p.user_id] = p
	update_user_list()
	update_lobby_list()


func join_stream(user):
	var stream = yield(socket.rpc_async("join_stream", user), "completed")
	if stream.is_exception():
		print("[join_stream]An error occured: %s" % stream)
		return
#	print("[join_stream]Successfully joined: %s" % stream)


### CHANNEL AND CHAT STUFFS ###
func join_chat_channel(roomname, type, persistence, hidden):
	channel = yield(socket.join_chat_async(roomname, type, persistence, hidden), "completed")
	if channel.is_exception():
		print("[NakamaRTAPI.Channel]An error occured: %s" % channel)
		return
	print("Now connected to channel id: '%s'" % [channel.id])


func _on_channel_presence_received(_presence):
	for p in _presence.joins:
		connected_users[p.user_id] = p
	for p in _presence.leaves:
		connected_users.erase(p.user_id)
	update_user_list()


func _on_channel_message_received(message):
	var p = JSON.parse(message.content)
	if typeof(p.result) == TYPE_DICTIONARY:
		var m = p.result["chat"]
		var make_message : String = str("\n[%s]: %s" %[message.username,m])
		if message.room_name == "Public":
			chat_main.chat.add_text(make_message)
		else:
			chat_main.chat.add_text(make_message)


func _on_ChatLobby_message_sent(text):
	var content = {"chat": text}
	yield(socket.write_chat_message_async(channel.id, content), "completed")


func _on_ChatMatch_message_sent(text):
	var content = {"chat": text}
	yield(socket.write_chat_message_async(channel.id, content), "completed")


### MATCH STUFFS ###
func open_match_room():
	$Lobby.show()
	dialog.hide()
	# Join match chat channel
	var roomname = MatchState.match_id
	var persistence = false
	var hidden = false
	var type = NakamaSocket.ChannelType.Room
	yield(join_chat_channel(roomname, type, persistence, hidden), "completed")
	chat_lobby.edit.grab_focus()

func join_match(id):
	var joined_match : NakamaRTAPI.Match = yield(socket.join_match_async(id), "completed")
	if joined_match.is_exception():
		print("\n[join_match_async]An error occured: %s" % joined_match)
		update_lobby_list()
		return
	print("Joined match: %s" % [joined_match.match_id])
	MatchState.update_match_data(joined_match)
	open_match_room()
	
	for presence in joined_match.presences:
		MatchState.connected_players[presence.user_id] = presence
#		print("\n[joinPresence]User id %s name %s'." % [presence.user_id, presence.username])


func _on_TopBar_on_Create_pressed():
	var created_match : NakamaRTAPI.Match = yield(socket.create_match_async(), "completed")
	if created_match.is_exception():
		print("\n[create_match_async]An error occured: %s." % created_match.exception)
		return 
	print("\nCreated new match with id %s." % created_match.match_id)
	
	MatchState.update_match_data(created_match, true)
	notify_new_match()
	$Lobby/VBoxContainer/HBoxContainer/Start.disabled = false
	open_match_room()


func _on_TopBar_on_Join_pressed():
	var text = top_bar.edit.text
	if text.empty():
		return
	join_match(text)
	top_bar.edit.text = ""


func _on_MatchList_item_activated(index):
	var text = match_list.get_item_text(index)
	join_match(text)


func _on_Leave_pressed():
	var leave : NakamaAsyncResult = yield(socket.leave_match_async(MatchState.match_id), "completed")
	if leave.is_exception():
		print("[leave_match_async]An error occured: %s" % leave)
		return
	print("Match left")
	MatchState.match_id = null
	chat_lobby.edit.grab_focus()
	$Lobby.hide()
	$Lobby/VBoxContainer/HBoxContainer/Start.disabled = true
	MatchState.leave()
	MatchState.connected_players.clear()
	chat_lobby.chat.clear()
	
	#Rejoin lobby chat channel
	var roomname = "Public"
	var persistence = false
	var hidden = false
	var type = NakamaSocket.ChannelType.Room
	yield(join_chat_channel(roomname, type, persistence, hidden), "completed")
	update_lobby_list()


func _on_match_presence_received(p_presence : NakamaRTAPI.MatchPresenceEvent):
	print("\n[matchPressenceReceived]%s:"%p_presence)
	for p in p_presence.joins:
		MatchState.on_player_joins(p)
	for p in p_presence.leaves:
		MatchState.on_player_leaves(p)
	update_player_list()


func _on_TopBar_on_Matchmake_pressed():
	dialog.dialog_text = ""
	dialog.get_ok().hide()
	dialog.popup_centered()
	var query = "*"
	var min_count = 2
	var max_count = 4
	var string_properties = { "region": "sea" }
	var numeric_properties = { "rank": 0 }
	matchmaker_ticket = yield(
		socket.add_matchmaker_async(query, min_count, max_count, string_properties, numeric_properties),
		"completed"
	)
	if matchmaker_ticket.is_exception():
		dialog.dialog_text = ("[add_matchmaker_async]An error occured: %s" % matchmaker_ticket)
		dialog.get_ok().show()
		matchmaker_ticket = null
		return
	print("Got ticket: %s" % [matchmaker_ticket])


func _on_matchmaker_matched(p_matched : NakamaRTAPI.MatchmakerMatched):
	print("\n[_on_matchmaker_matched]Received MatchmakerMatched message: %s" % p_matched)
	var joined_match : NakamaRTAPI.Match = yield(socket.join_matched_async(p_matched), "completed")
	if joined_match.is_exception():
		print("\n[join_matched_async]An error occured: %s" % joined_match)
		return
	print("\n[matchmakerMatched]Joined match: %s" % [joined_match])
	dialog.hide()
	MatchState.match_id = joined_match.match_id

	for presence in joined_match.presences:
		MatchState.connected_players[presence.user_id] = presence
		print("\n[matchmakerMatchedPresence]User id %s name %s'." % [presence.user_id, presence.username])
	update_player_list()
	open_match_room()


func _on_matchmake_dialog_closed():
	var removed : NakamaAsyncResult = yield(socket.remove_matchmaker_async(matchmaker_ticket.ticket), "completed")
	if removed.is_exception():
		print("[remove_matchmaker_async]An error occured: %s" % removed)
		return
	print("Removed from matchmaking %s" % [matchmaker_ticket.ticket])
	matchmaker_ticket = null


### GETTERS & UI UPDATES ###
func get_match_list():
	var list = yield(socket.rpc_async("match_list"), "completed")
	var payload = parse_json(list.payload)
	return payload
	
func update_lobby_list():
	match_list.clear()
	var list = yield(get_match_list(), "completed")
	for _match in list:
#		print(_match)
		match_list.add_item(_match.match_id, null, true)
		
	for i in range(0,match_list.get_item_count()):
		match_list.set_item_tooltip_enabled(i, false)


func update_player_list():
	player_list.clear()
	for p in MatchState.connected_players:
		var opponent = MatchState.connected_players[p]
		player_list.add_item(opponent.username, null, true)
		print("[update_player_list]Connected players: %s" % [opponent.username])
	
	for i in range(0,player_list.get_item_count()):
		player_list.set_item_tooltip_enabled(i, false)


func update_user_list():
	user_list.clear()
	for u in connected_users:
		user_list.add_item(connected_users[u].username, null, true)
	for i in range(0,user_list.get_item_count()):
		user_list.set_item_tooltip_enabled(i, false)


#func get_users():
#	var session = NClient.session
#	var ids = []
#	for u in connected_users:
#		ids.append(connected_users[u].user_id)
#	var result : NakamaAPI.ApiUsers = yield(client.get_users_async(session, ids, null, null), "completed")
#	if result.is_exception():
#		print("An error occured: %s" % result)
#		return
#	for u in result.users:
#		print("User id '%s' username '%s'" % [u.id, u.username])


### EXPERIMENTAL ###
func notify_new_match():
	var data = yield(socket.rpc_async("notify_new_match"), "completed")
	if data.is_exception():
		print("[notify_new_match]An error occured: %s" % data)
		return
	print("[notify_new_match]Successfully broadcast match to all connect users")


func _on_stream_state_received(p_state : NakamaRTAPI.StreamData):
	var data = parse_json(p_state.state)	
	if data == my_account.user.id:
		print("Do not notifiy self of creating match")
		return
	print("Received Notification of new created match")
	update_lobby_list()


func _on_stream_presence_received(_p_stream_presence_event):
	pass


func _on_Start_pressed():
	MatchState.start_game()


func on_game_start():
	$Game.show()


func _on_Button_pressed():
	rpc("myTestRPC")


remotesync func myTestRPC():
	print("RPC WORKS")
