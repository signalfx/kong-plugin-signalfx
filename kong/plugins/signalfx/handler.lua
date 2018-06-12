local basic_serializer = require 'kong.plugins.log-serializers.basic'
local BasePlugin = require 'kong.plugins.base_plugin'
local resty_lock = require 'resty.lock'
local tostr = require 'pl.pretty'.write
local stringx = require 'pl.stringx'
local ngx_timer_at = ngx.timer.at
local ngx_null = ngx.null
local ngx_log = ngx.log
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN
local ERR = ngx.ERR

local unpack = unpack
local fmt = string.format
local tonumber = tonumber
local tostring = tostring
local char = string.char
local gsub = string.gsub


local SignalHandler = BasePlugin:extend()
SignalHandler.PRIORITY = 12

SignalHandler.version = 1
SignalHandler.context_key = '_SFx'
SignalHandler.null = char(0)
SignalHandler.dlim = char(31)

local shm = ngx.shared.kong_signalfx_aggregation or ngx.shared.kong_cache

local function log(level, ...)
  ngx_log(level, '[signalfx] ', ...)
end

local function ldebug(...)
  log(DEBUG, ...)
end

local function lwarn(...)
  log(WARN, ...)
end

local function lerr(...)
  log(ERR, ...)
end

local function nsub(s)
  return gsub(s, '%z', 'null')
end

function SignalHandler:new()
  SignalHandler.super.new(self, 'signalfx')
end

function SignalHandler:get_context_key(message, config)
  local null = self.null
  local api_id, api_name, service_id, service_name, route_id = null, null, null, null, null

  if message.api ~= nil then
    api_id = message.api.id or null
    api_name = message.api.name or null
  end
  if message.service ~= nil then
    service_id = message.service.id or null
    if message.service.name ~= ngx_null then
      service_name = message.service.name or null
    end
  end
  if message.route ~= nil then
    route_id = message.route.id or null
  end
  local req_method = null
  if config.aggregate_by_http_method then
    req_method = message.request.method or null
  end

  local context_key = self.context_key
  for _, k in ipairs({self.version, api_id, api_name, service_id, service_name, route_id, req_method}) do
    context_key = context_key .. self.dlim .. k
  end
  return context_key
end

function SignalHandler:decode_metrics(metric_string)
  local tokens = stringx.split(metric_string, ',')
  local request_count = tonumber(tokens[1])
  local request_latency = tonumber(tokens[2])
  local kong_latency = tonumber(tokens[3])
  local proxy_latency = tonumber(tokens[4])
  local request_size = tonumber(tokens[5])
  local response_size = tonumber(tokens[6])

  local status_vals = {unpack(tokens, 7, #tokens)}
  local statuses = {}
  for _, v in ipairs(status_vals) do
    local val = stringx.split(v, ':')
    statuses[val[1]] = {count=tonumber(val[2]),
                        proxy_latency=tonumber(val[3]),
                        request_size=tonumber(val[4]),
                        response_size=tonumber(val[5])}
  end

  return request_count, request_latency, kong_latency, proxy_latency, request_size, response_size, statuses
end

function SignalHandler:encode_metrics(request_count, request_latency, kong_latency, proxy_latency, request_size,
                                      response_size, statuses)
  local packed = stringx.join(',', {request_count, request_latency,
                                    kong_latency, proxy_latency,
                                    request_size, response_size})
  for sc, vals in pairs(statuses) do
    packed = packed .. ',' .. sc
    for _, k in ipairs({vals.count, vals.proxy_latency, vals.request_size, vals.response_size}) do
      packed = packed .. ':' .. k
    end
  end
  return packed
end

function SignalHandler.aggregate(premature, self, config, message)
  if premature then return end
  local lock, err = resty_lock:new('kong_signalfx_locks')
  if not lock then
    lerr('Unable to create lock for request/response context. Aborting aggregation: ', err)
    return
  end

  ldebug('Including message in aggregation: ', tostr(message))
  local context_key = self:get_context_key(message, config)
  ldebug(fmt('Aggregation context: %s.', nsub(context_key)))

  local _, err = lock:lock(context_key)
  if err then
    lerr(fmt('Unable to lock aggregation context %s. Aborting.', nsub(context_key)))
    return
  end

  local current, _ = shm:get(context_key)
  if current == nil then
    current = '0,0,0,0,0,0'
  end

  local request_count, request_latency, kong_latency, proxy_latency,
  request_size, response_size, statuses = self:decode_metrics(current)

  request_count = request_count + 1
  request_latency = request_latency + message.latencies.request
  kong_latency = kong_latency + message.latencies.kong
  local p_lat = message.latencies.proxy
  if p_lat == -1 then  --proxied requests without routes.
    p_lat = 0
  end
  proxy_latency = proxy_latency + p_lat
  request_size = request_size + message.request.size
  response_size = response_size + message.response.size
  local resp_status = tostring(message.response.status or 0)
  local status = statuses[resp_status] or {count=0, proxy_latency=0, request_size=0, response_size=0}
  status.count = status.count + 1
  status.proxy_latency = status.proxy_latency + p_lat
  status.request_size = status.request_size + message.request.size
  status.response_size = status.response_size + message.response.size
  statuses[resp_status] = status
  local updated = self:encode_metrics(request_count, request_latency, kong_latency, proxy_latency,
                                 request_size, response_size, statuses)
  local succ, err, forcible = shm:set(context_key, updated)
  if not succ then
    lerr(fmt('Failed to update aggregation for %s: %s.', nsub(context_key), err))
  end
  if forcible then
    lerr('Valid aggregates have been removed from the key value store. ',
         'Please increase the size of the kong_signalfx_aggregation shared dict.')
  end
  local ok, err = lock:unlock()
  if not ok then
    lwarn('Failed to unlock. ', err)
  end
end

function SignalHandler:log(config)
  SignalHandler.super.log(self)
  local message = basic_serializer.serialize(ngx)
  local ok, err = ngx_timer_at(0, SignalHandler.aggregate, self, config, message)
  if not ok then
    lerr('Failed to create timer: ', err)
  end
end

return SignalHandler
