local startswith = require 'pl.stringx'.startswith
local capture = ngx.location.capture

local tonumber = tonumber
local find = string.find
local sub = string.sub

local shm = ngx.shared.kong_signalfx_aggregation or ngx.shared.kong_cache

return {
  ['/signalfx'] = {
    GET = function(self, dao, helpers)
      local r = capture('/nginx_status')
      if r.status ~= 200 then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(r.body)
      end

      local var = ngx.var
      local accepted, handled, total = select(3, find(r.body, 'accepts handled requests\n (%d*) (%d*) (%d*)'))

      local keys = shm:get_keys(0)
      local aggregates = {}
      for _, k in pairs(keys) do
        local value, _ = shm:get(k)
        if startswith(k, '_SFx') then
          aggregates[sub(k, 6, #k)] = value
        end
      end

      local status_response = {
        server = {
          connections_active = tonumber(var.connections_active),
          connections_reading = tonumber(var.connections_reading),
          connections_writing = tonumber(var.connections_writing),
          connections_waiting = tonumber(var.connections_waiting),
          connections_accepted = tonumber(accepted),
          connections_handled = tonumber(handled),
          total_requests = tonumber(total)
        },
        database = {
          database_reachable = false,
        },
        signalfx = aggregates,
      }

      local dbOk = false
      local dbErr = nil
      if dao.db then
        dbOk, dbErr = dao.db:reachable()
      else
        dbOk, dbErr = kong.db.connector:connect()
      end

      if not dbOk then
        ngx.log(ngx.ERR, 'failed to reach database as part of ',
                         '/signalfx endpoint: ', dbErr)
      else
        status_response.database.database_reachable = true
      end

      if helpers.responses then
        return helpers.responses.send_HTTP_OK(status_response)
      end
      return kong.response.exit(200, status_response)
    end
  }
}
