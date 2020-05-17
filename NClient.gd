# MyClient.gd
extends Node

const STORE_FILE = "user://store.ini"
const STORE_SECTION = "nakama"
const STORE_KEY = "session"

var user_id
var session : NakamaSession = null
var rand: RandomNumberGenerator = RandomNumberGenerator.new()


onready var client : NakamaClient = Nakama.create_client("defaultkey", "192.168.99.102", 7350, "http")
onready var socket : NakamaSocket = Nakama.create_socket_from(client)

func _ready():
	rand.seed = OS.get_unix_time()
# warning-ignore:return_value_discarded
	socket.connect("connected", self, "_on_socket_connected")
# warning-ignore:return_value_discarded
	socket.connect("closed", self, "_on_socket_closed")
# warning-ignore:return_value_discarded
	socket.connect("received_error", self, "_on_socket_error")
	yield(_connect_to_server(), "completed")
	

func _connect_to_server():
	var cfg = ConfigFile.new()
	cfg.load(STORE_FILE)
	var token = cfg.get_value(STORE_SECTION, STORE_KEY, "")
	if !token:
		var restored_session = NakamaClient.restore_session(token)
		if restored_session.valid and not restored_session.expired:
			session = restored_session
			yield(socket.connect_async(session), "completed")
#			print(session._to_string())
			return
#	var deviceid = OS.get_unique_id() # This is not supported by Godot in HTML5, use a different way to generate an id, or a different authentication option.
#	session = yield(client.authenticate_device_async(deviceid), "completed")
	session = yield(client.authenticate_custom_async(_random_id()), "completed")
	if not session.is_exception():
		cfg.set_value(STORE_SECTION, STORE_KEY, session.token)
		cfg.save(STORE_FILE)
		yield(socket.connect_async(session), "completed")
#	print(session._to_string())
	
func _get_account(): 
	var account = yield(client.get_account_async(session), "completed")
	if account.is_exception():
		print("We got an exception")
		return
	user_id = account.user.id
#	var user = account.user
#	print("User id '%s' and username '%s'." % [user.id, user.username])
#	print("User's wallet: %s." % account.wallet)
#	print(account)
	return account

func _random_id():
	var ALFNUM = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var _alfnum = ALFNUM.to_ascii()
	var _id = ""
	for _i in range(0, 10):
		_id += char(_alfnum[rand.randi_range(0, ALFNUM.length()-1)])
	return _id

func _on_socket_connected():
	print("Socket connected.")

func _on_socket_closed():
	print("Socket closed.")

func _on_socket_error(err):
	printerr("Socket error %s" % err)
