extends Node

signal game_start()

onready var socket = NClient.socket
onready var my_user_id
var webrtc_multiplayer : WebRTCMultiplayer
var webrtc_peer : WebRTCPeerConnection
var data_channel : WebRTCDataChannel
var players : Dictionary
var webrtc_peers : Dictionary
var connected_players : Dictionary
var webrtc_peers_connected : Dictionary
var state = 5
var match_id
var next_peer_id : int
var my_session_id
var is_host = false
var options = {
	"negotiated": true, # When set to true (default off), means the channel is negotiated out of band. "id" must be set too. data_channel_received will not be called.
	"id": 1, # When "negotiated" is true this value must also be set to the same value on both peer.

#	# Only one of maxRetransmits and maxPacketLifeTime can be specified, not both. They make the channel unreliable (but also better at real time).
#	"maxRetransmits": 1, # Specify the maximum number of attempt the peer will make to retransmits packets if they are not acknowledged.
#	"maxPacketLifeTime": 100, # Specify the maximum amount of time before giving up retransmitions of unacknowledged packets (in milliseconds).
#	"ordered": true, # When in unreliable mode (i.e. either "maxRetransmits" or "maxPacketLifetime" is set), "ordered" (true by default) specify if packet ordering is to be enforced.
#
#	"protocol": "my-custom-protocol", # A custom sub-protocol string for this channel.
}
enum ConnectionState {
	STATE_NEW = 0, # — The connection is new, data channels and an offer can be created in this state.
	STATE_CONNECTING = 1, # — The peer is connecting, ICE is in progress, none of the transports has failed.
	STATE_CONNECTED = 2, # — The peer is connected, all ICE transports are connected.
	STATE_DISCONNECTED = 3, # — At least one ICE transport is disconnected.
	STATE_FAILED = 4, # — One or more of the ICE transports failed.
	STATE_CLOSED = 5 #— The peer connection is closed (after calling close for example).
}
enum OP_CODE {
	RTC = 1,
	JOIN = 2,
	POST_JOIN = 3,
	P2P = 4
}
func _ready():
	socket.connect("received_match_state", self, "_on_match_state_received")


func _on_match_state_received(p_state : NakamaRTAPI.MatchData):
	match p_state.op_code:

		OP_CODE.RTC:
			var data = parse_json(p_state.data)
			if data.target == my_session_id:
				var session_id = p_state.presence.session_id
				webrtc_peer = webrtc_peers[session_id]
				match data.method:
					'set_remote_description':
						webrtc_peer.set_remote_description(data.type, data.sdp)
					'add_ice_candidate':
						webrtc_peer.add_ice_candidate(data.media, data.index, data.name)
					'reconnect':
						webrtc_multiplayer.remove_peer(players[session_id]['peer_id'])
#						_webrtc_reconnect_peer(players[session_id])

		OP_CODE.JOIN:
			print("[OP_CODE.JOIN]received")
			var data = parse_json(p_state.data)
			players = data.players
			next_peer_id = data.next_peer_id
			var host_id = data.host_id
			set_peer_id(host_id)

		OP_CODE.POST_JOIN:
			var data = parse_json(p_state.data)
			next_peer_id = data.next_peer_id
			players[data.session_id] = data.player

		OP_CODE.P2P:
			webrtc_multiplayer.initialize(players[my_session_id].peer_id)
			get_tree().set_network_peer(webrtc_multiplayer)
			peer_to_peer()


func update_match_data(_match, host = false):
	_create_webrtc_multiplayer()
	if host:
		is_host = true
		next_peer_id = 1

	match_id = _match.match_id
	my_session_id = _match.self_user.session_id


func on_player_joins(u):
	connected_players[u.user_id] = u

	# populate players list
	for user_id in connected_players:
		# skip if self is already in the list
		if players.has(connected_players[user_id].session_id):
			continue

		var session_id = connected_players[user_id].session_id
		players[session_id] = connected_players[user_id].to_dictionary()
		print("ADDED THE FUCKING PLAYER WOOHOOO\n%s" %players[session_id])
	print("done populating players list")

	if is_host:
		if u.user_id != my_user_id:
			var target = [u]
			var op_code = 2
			var data = {"players": players, "next_peer_id" : next_peer_id, "host_id" : my_user_id}
			send_data(target, op_code, JSON.print(data))
		else:
			set_peer_id()


func on_player_leaves(p):
	connected_players.erase(p.user_id)
	players.erase(p.session_id)


func set_peer_id(host_id = null):
	players[my_session_id]["peer_id"] = next_peer_id
	next_peer_id += 1

	#send the update next_peer_id back to host
	if !is_host:
		var target = [connected_players[host_id]]
		var op_code = 3
		var data = {"session_id": my_session_id, "player": players[my_session_id], "next_peer_id" : next_peer_id}
		send_data(target, op_code, JSON.print(data))


func start_game():
	if is_host:
		print("is host")
		webrtc_multiplayer.initialize(1)
		get_tree().set_network_peer(webrtc_multiplayer)
		var target = connected_players
		target.erase(my_user_id)
		send_data(target, 4, " ")
		peer_to_peer()


func peer_to_peer():
	for session_id in players:
		if session_id == my_session_id:
			continue
		_webrtc_connect_peer(players[session_id])


# send data to other client, could be used to do RTC Signaling?
func send_data(target, op_code, data):
	var msg = yield(socket.send_match_state_async(match_id, op_code, data, target), "completed")
	if msg.is_exception():
		print("[send_match_state_async]An error occured: %s" % msg)
		return


func leave():
	# WebRTC disconnect.
	if webrtc_multiplayer:
		print("closing webrtc_multiplayer")
		webrtc_multiplayer.disconnect("peer_connected", self, "_on_webrtc_peer_connected")
		webrtc_multiplayer.disconnect("peer_disconnected", self, "_on_webrtc_peer_disconnected")
		webrtc_multiplayer.close()
		get_tree().set_network_peer(null)

	# Initialize all the variables to their default state.
	my_session_id = null
	_create_webrtc_multiplayer()
	webrtc_peers = {}
	webrtc_peers_connected = {}
	players = {}
	next_peer_id = 1


func _create_webrtc_multiplayer():	
	webrtc_multiplayer = WebRTCMultiplayer.new()
	webrtc_multiplayer.connect("peer_connected", self, "_on_webrtc_peer_connected")
	webrtc_multiplayer.connect("peer_disconnected", self, "_on_webrtc_peer_disconnected")


func _webrtc_connect_peer(u: Dictionary):
	print("connecting peer")
	# Don't add the same peer twice!
	if webrtc_peers.has(u['session_id']):
		return
	
	webrtc_peer = WebRTCPeerConnection.new()
	webrtc_peer.initialize({
		"iceServers": [{ "urls": ["stun:stun.l.google.com:19302"] }]
	})
	webrtc_peer.connect("data_channel_received", self, "_on_data_channel_received")
	webrtc_peer.connect("session_description_created", self, "_on_webrtc_peer_session_description_created", [u['user_id'],u['session_id']])
	webrtc_peer.connect("ice_candidate_created", self, "_on_webrtc_peer_ice_candidate_created", [u['user_id'],u['session_id']])
#	data_channel = webrtc_peer.create_data_channel("label", options)
	state = 0
	webrtc_peers[u['session_id']] = webrtc_peer
	
	webrtc_multiplayer.add_peer(webrtc_peer, u.peer_id)
	
	if my_session_id.casecmp_to(u['session_id']) < 0:
		var result = webrtc_peer.create_offer()
		if result != OK:
			emit_signal("error", "Unable to create WebRTC offer")


func _on_webrtc_peer_session_description_created(type : String, sdp : String, user_id : String, session_id : String):
	webrtc_peer = webrtc_peers[session_id]
	webrtc_peer.set_local_description(type, sdp)

	# Send this data to the peer so they can call call .set_remote_description().
	var target = [connected_players[user_id]]
	var op_code = 1
	var data = JSON.print({
				method = "set_remote_description",
				target = session_id,
				type = type,
				sdp = sdp,
			})
	send_data(target, op_code, data)


func _on_webrtc_peer_ice_candidate_created(media : String, index : int, name : String, user_id : String, session_id : String):
	# Send this data to the peer so they can call .add_ice_candidate()
	var target = [connected_players[user_id]]
	var op_code = 1
	var data = JSON.print({
				method = "add_ice_candidate",
				target = session_id,
				media = media,
				index = index,
				name = name,
			})
	send_data(target, op_code, data)


func _on_data_channel_received(channel: Object):
	pass
	

func _on_webrtc_peer_connected(peer_id: int):
	for session_id in players:
		if players[session_id]['peer_id'] == peer_id:
			webrtc_peers_connected[session_id] = true

	# We have a WebRTC peer for each connection to another player, so we'll have one less than
	# the number of players (ie. no peer connection to ourselves).
	emit_signal("game_start")
	
#func send_message(message):
#	data_channel.put_packet(message.to_utf8())
	
#func _process(_delta):
#	match state:
#		ConnectionState.STATE_NEW:
#			webrtc_peer.poll()
#			if data_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
#				while data_channel.get_available_packet_count() > 0:
#					print(" received: ", data_channel.get_packet().get_string_from_utf8())
