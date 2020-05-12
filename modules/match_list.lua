local nk = require("nakama")

local function match_list()
  limit = 10
  local matches = nk.match_list(limit)

  nk.logger_info(("Payload: %q"):format(matches))

  return nk.json_encode(matches)
end

local function join_stream(context, _)
  local stream_id = { mode = 0 }
  local hidden = false
  local persistence = false
  nk.stream_user_join(context.user_id, context.session_id, stream_id, hidden, persistence)
  return context.username
end

local function notify_new_match()
  local stream_id = { mode = 0 }
  local payload = nk.json_encode("")
  nk.stream_send(stream_id, payload)
end

nk.register_rpc(join_stream, "join_stream")
nk.register_rpc(match_list, "match_list")
nk.register_rpc(notify_new_match, "notify_new_match")