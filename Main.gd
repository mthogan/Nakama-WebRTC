extends Node

var webrtcScript = preload("res://WebRTC.gd")
var webrtc : Node
onready var socket = NClient.socket
onready var channel : NakamaRTAPI.Channel
onready var client = NClient.client
var my_account
onready var webrtc_multiplayer = NClient.webrtc_multiplayer
onready var dialog = $MatchmakeDialog
var connected_users = {}
var available_matches = {}
var match_data
var matchmaker_ticket : NakamaRTAPI.MatchmakerTicket
var my_session_id

func _ready():
	socket.connect("connected", self, "_on_socket_connected")
	socket.connect("closed", self, "_on_closed")
	socket.connect("received_channel_presence", self, "_on_channel_presence_received")
	socket.connect("received_channel_message", self, "_on_channel_message_received")
	socket.connect("received_match_presence", self, "_on_match_presence_received")
	socket.connect("received_matchmaker_matched", self, "_on_matchmaker_matched")
	socket.connect("received_stream_presence", self, "_on_stream_presence_received")
	socket.connect("received_stream_state", self, "_on_stream_state_received")
	dialog.get_close_button().connect("pressed", self, "_on_matchmake_dialog_closed")
	$HBoxContainer/VBoxContainer/ChatLobby/Chat/LineEdit.grab_focus()

func _on_socket_connected():
	#Fetch account info
	my_account = yield(NClient._get_account(), "completed")
	join_stream(my_account.user)
	#Join lobby chat channel
	var roomname = "Public"
	var persistence = false
	var hidden = false
	var type = NakamaSocket.ChannelType.Room
	yield(join_chat_channel(roomname, type, persistence, hidden), "completed")
	for p in channel.presences:
		print("[init channel here %s]"%p)
		connected_users[p.user_id] = p
	update_player_list()
	update_lobby_list()

func join_stream(user):
	var stream = yield(socket.rpc_async("join_stream", user), "completed")
	if stream.is_exception():
		print("[join_stream]An error occured: %s" % stream)
		return
	print("[join_stream]Successfully joined: %s" % stream)
	
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
	update_player_list()


func _on_channel_message_received(message):
	var p = JSON.parse(message.content)
	if typeof(p.result) == TYPE_DICTIONARY:
		var m = p.result["chat"]
		var make_message : String = str("\n[%s]: %s" %[message.username,m])
		if message.room_name == "Public":
			$HBoxContainer/VBoxContainer/ChatLobby/Chat.add_text(make_message)
		else:
			$Panel/VBoxContainer/HBoxContainer2/ChatMatch/Chat.add_text(make_message)


func _on_ChatLobby_message_sent(text):
	var content = {"chat": text}
	yield(socket.write_chat_message_async(channel.id, content), "completed")


func _on_ChatMatch_message_sent(text):
	var content = {"chat": text}
	yield(socket.write_chat_message_async(channel.id, content), "completed")


### MATCH STUFFS ###
func open_match_room():
	$Panel.show()
	dialog.hide()
	# Join match chat channel
	var roomname = MatchState.match_id
	var persistence = false
	var hidden = false
	var type = NakamaSocket.ChannelType.Room
	yield(join_chat_channel(roomname, type, persistence, hidden), "completed")
	$Panel/VBoxContainer/HBoxContainer2/ChatMatch/Chat/LineEdit.grab_focus()

func join_match(id):
	var joined_match : NakamaRTAPI.Match = yield(socket.join_match_async(id), "completed")
	if joined_match.is_exception():
		print("\nAn error occured: %s" % joined_match)
		return
	print("Joined match: %s" % [joined_match])	
	MatchState.match_id = joined_match.match_id
	open_match_room()
#	var webrtc_peer := WebRTCPeerConnection.new()
#	webrtc_peer.initialize({
#		"iceServers": [{ "urls": ["stun:stun.l.google.com:19302"] }]
#	})
#	webrtc_peer.connect("session_description_created", self, "_on_webrtc_peer_session_description_created", [u['session_id']])
#	webrtc_peer.connect("ice_candidate_created", self, "_on_webrtc_peer_ice_candidate_created", [u['session_id']])
	
	for presence in joined_match.presences:
		MatchState.connected_opponents[presence.user_id] = presence
		print("\n[joinPresence]User id %s name %s'." % [presence.user_id, presence.username])
		
	new_rtc("join")
	
func _on_Create_pressed():
	var created_match : NakamaRTAPI.Match = yield(socket.create_match_async(), "completed")
	if created_match.is_exception():
		print("\nAn error occured: %s" % created_match.exception)
		return 
	print("\nCreated new match with id %s.", created_match.match_id)
	MatchState.match_id = created_match.match_id
	my_session_id = created_match.self_user.session_id
#	match_data = created_match
#	match_data[]
#	webrtc_multiplayer.initialize(1)
#	get_tree().set_network_peer(webrtc_multiplayer)
	notify_new_match()
	open_match_room()
	
	new_rtc("create")



func _on_Join_pressed():
	var text = $HBoxContainer/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/LineEdit.text
	if text.empty():
		return
	join_match(text)
	$HBoxContainer/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/LineEdit.text = ""
	
	
func _on_MatchList_item_activated(index):
	var match_list= $HBoxContainer/VBoxContainer/VBoxContainer/MatchList
	var text = match_list.get_item_text(index)
	var metadata = match_list.get_item_metadata(index)
	print("text %s" %text)
	print("metadata %s" %metadata)
	join_match(text)


func _on_Leave_pressed():
	var leave : NakamaAsyncResult = yield(socket.leave_match_async(MatchState.match_id), "completed")
	if leave.is_exception():
		print("An error occured: %s" % leave)
		return
	print("Match left")
	MatchState.match_id = null
	$HBoxContainer/VBoxContainer/ChatLobby/Chat/LineEdit.grab_focus()
	$Panel.hide()
	$Panel/VBoxContainer/HBoxContainer2/ChatMatch/Chat.clear()
	
#	remove_child(get_node("Node"))
	get_node("Node").queue_free()
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
		MatchState.connected_opponents[p.user_id] = p
	for p in p_presence.leaves:
		MatchState.connected_opponents.erase(p.user_id)
	update_opponent_list()


func _on_Matchmake_pressed():
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
		dialog.dialog_text = ("An error occured: %s" % matchmaker_ticket)
		dialog.get_ok().show()
		matchmaker_ticket = null
		return
	print("Got ticket: %s" % [matchmaker_ticket])
func _on_matchmaker_matched(p_matched : NakamaRTAPI.MatchmakerMatched):
	print("\n[matchmakerMatched]Received MatchmakerMatched message: %s" % p_matched)
	var joined_match : NakamaRTAPI.Match = yield(socket.join_matched_async(p_matched), "completed")
	if joined_match.is_exception():
		print("\nAn error occured: %s" % joined_match)
		return
	dialog.hide()
	
	MatchState.match_id = joined_match.match_id
	open_match_room()
	print("\n[matchmakerMatched]Joined match: %s" % [joined_match])
	for presence in joined_match.presences:
		MatchState.connected_opponents[presence.user_id] = presence
		print("\n[matchmakerMatchedPresence]User id %s name %s'." % [presence.user_id, presence.username])
	update_opponent_list()


func _on_matchmake_dialog_closed():
	var removed : NakamaAsyncResult = yield(socket.remove_matchmaker_async(matchmaker_ticket.ticket), "completed")
	if removed.is_exception():
		print("An error occured: %s" % removed)
		return
	print("Removed from matchmaking %s" % [matchmaker_ticket.ticket])
	matchmaker_ticket = null
	

### GETTERS & UI UPDATES ###
func get_match_list():
	var match_list = yield(socket.rpc_async("match_list"), "completed")
	var payload = parse_json(match_list.payload)
	return payload
	
func update_lobby_list():
	var matchList = $HBoxContainer/VBoxContainer/VBoxContainer/MatchList
	matchList.clear()
	var match_list = yield(get_match_list(), "completed")
	for _match in match_list:
		print(_match)
		matchList.add_item(_match.match_id, null, true)
		
	for i in range(0,matchList.get_item_count()):
		matchList.set_item_tooltip_enabled(i, false)
		
func update_opponent_list():
	$Panel/VBoxContainer/HBoxContainer2/ItemList.clear()
	for p in MatchState.connected_opponents:
		var opponent = MatchState.connected_opponents[p]
		$Panel/VBoxContainer/HBoxContainer2/ItemList.add_item(opponent.username, null, true)
		print("\n[update_opponent_list]Connected opponents: %s" % [opponent.username])
	
	for i in range(0,$Panel/VBoxContainer/HBoxContainer2/ItemList.get_item_count()):
		$Panel/VBoxContainer/HBoxContainer2/ItemList.set_item_tooltip_enabled(i, false)
		
func update_player_list():
	$HBoxContainer/ItemList.clear()
	for u in connected_users:
		$HBoxContainer/ItemList.add_item(connected_users[u].username, null, true)
	for i in range(0,$HBoxContainer/ItemList.get_item_count()):
		$HBoxContainer/ItemList.set_item_tooltip_enabled(i, false)
		
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
	print("[notify_new_match]Successfully joined: %s" % data)
	
func _on_stream_state_received(p_state : NakamaRTAPI.StreamData):
	print("Received data from stream: %s" % [p_state.stream])
#	print("Data: %s" % [parse_json(p_state.state)])
	update_lobby_list()
	
func _on_stream_presence_received(_p_stream_presence_event):
	pass


func _on_Button3_pressed():
	webrtc.send_message("Hi from %s" %NClient.user_id)

func new_rtc(type: String):
	webrtc = webrtcScript.new()
	add_child(webrtc, true)
	yield(get_tree().create_timer(1), "timeout")
	if type == "create":
		webrtc.register(NClient.user_id)
		return
	elif type == "join":
		webrtc.join(NClient.user_id)
		return
