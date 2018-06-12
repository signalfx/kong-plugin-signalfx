local handler = require 'kong.plugins.signalfx.handler'
local fmt = string.format

local dlim = handler.dlim
local null = handler.null


describe("Aggregation Utilities", function()
  local http_config, no_http_config
  local api_message, service_message, objectless_message
  local api_id, api_name
  local service_id, service_name
  local route_id
  local http_method

  setup(function()
    http_config = {aggregate_by_http_method = true}
    no_http_config = {aggregate_by_http_method = false}
    api_id = "fff7148b-50c0-4503-8cc4-6cca2708535a"
    api_name = "APISPBJ-sc_ZKhwilj"
    service_id = "d3fde621-0610-4b42-91a3-4cb7779e09c2"
    service_name = "ServiceKs3Oul"
    route_id = "18c1ebe2-c73d-41a8-ab2d-67f7e6b15c41"
    http_method = "DELETE"

    api_message = {
      latencies = { request = 0, kong = 0, proxy = -1 }, service = { },
      request = {
        querystring = { },
        size = "183", uri = "/uriUk95ny8rUC6ohorAa3S", url = "http://kong:8000/uriUk95ny8rUC6ohorAa3S",
        headers = { host = "kong:8100", connection = "keep-alive", accept = "*/*" },
        method = http_method
      },
      tries = { }, client_ip = "172.20.0.1",
      api = {
        created_at = 1529345607524, strip_uri = true, id = api_id, name = api_name , http_if_terminated = false,
        https_only = false, upstream_url = "http://service_one_b/echo",
        uris = { "/urio.J~srm1ezi", "/uriUk95ny8rUC6ohorAa3S" },
        preserve_host = false, upstream_connect_timeout = 60000, upstream_read_timeout = 60000,
        upstream_send_timeout = 60000, retries = 5
      },
      upstream_uri = "/echo",
      response = {
        headers = {
          ["content-type"] = "application/json; charset=utf-8", server = "kong/0.13.1", connection = "close",
          ["transfer-encoding"] = "chunked", ["www-authenticate"] = "Basic realm=\"kong\""
        },
        status = 401, size = "262"
      },
      route = { }, started_at = 1529345610951
    }
    service_message = {
      latencies = { request = 0, kong = 0, proxy = -1 },
      service = {
        host = "service_two_a", created_at = 1529346122, connect_timeout = 60000, id = service_id,
        protocol = "https", name = service_name, read_timeout = 60000, port = 443,
        path = "/echo", updated_at = 1529346122, retries = 5, write_timeout = 60000
      },
      request = {
        querystring = { }, size = "151", uri = "/path.ihTRq", url = "https://kong:8443/path.ihTRq",
        headers = { host = "kong:8543", connection = "keep-alive", accept = "*/*" }, method = http_method,
      },
      tries = { }, client_ip = "172.20.0.1", api = { }, upstream_uri = "/echo",
      response = {
        headers = {
          connection = "close", ["content-type"] = "application/json; charset=utf-8",
          ["www-authenticate"] = "Basic realm=\"kong\"", server = "kong/0.13.1"
        },
        status = 401, size = "196"
      },
      route = {
        created_at = 1529346122, strip_path = true, hosts = "userdata: NULL", preserve_host = false,
        regex_priority = 0, updated_at = 1529346122, paths = { "/path.ihTRq" },
        service = { id = service_id, }, methods = "userdata: NULL", protocols = { "http", "https" }, id = route_id,
      },
      started_at = 1529346128222
    }
    objectless_message = {
      latencies = { request = 0, kong = 0, proxy = -1 },
      request = {
        querystring = { }, size = "79", uri = "/", url = "http://127.0.0.1:8000/",
        headers = { host = "127.0.0.1:8000", accept = "*/*", }, method = http_method
      },
      client_ip = "127.0.0.1", upstream_uri = "",
      response = {
        headers = {
          connection = "close", ["content-type"] = "application/json; charset=utf-8", server = "kong/0.13.1"
        },
        status = 404, size = "155"
      },
      started_at = 1529346198372
    }

  end)

  describe("Basic", function()
    it("Builds API message context key correctly", function()
      local expected_prefix = handler.context_key .. dlim .. handler.version .. dlim .. api_id .. dlim .. api_name ..
                              dlim .. null .. dlim .. null .. dlim .. null .. dlim
      local http_context = handler:get_context_key(api_message, http_config)
      assert.equal(http_context, expected_prefix .. http_method)

      local no_http_context = handler:get_context_key(api_message, no_http_config)
      assert.equal(no_http_context, expected_prefix .. null)
    end)

    it("Builds Service message context key correctly", function()
      local expected_prefix = handler.context_key .. dlim .. handler.version .. dlim .. null .. dlim .. null ..
                              dlim .. service_id .. dlim .. service_name .. dlim .. route_id .. dlim
      local http_context = handler:get_context_key(service_message, http_config)
      assert.equal(http_context, expected_prefix .. http_method)

      local no_http_context = handler:get_context_key(service_message, no_http_config)
      assert.equal(no_http_context, expected_prefix .. null)
    end)

    it("Builds objectless message context key correctly", function()
      local expected_prefix = handler.context_key .. dlim .. handler.version .. dlim .. null .. dlim .. null ..
                              dlim .. null .. dlim .. null .. dlim .. null .. dlim
      local http_context = handler:get_context_key(objectless_message, http_config)
      assert.equal(http_context, expected_prefix .. http_method)

      local no_http_context = handler:get_context_key(objectless_message, no_http_config)
      assert.equal(no_http_context, expected_prefix .. null)
    end)

    it("Encodes metric strings as expected", function()
      local request_count = 100
      local request_latency = 1000
      local kong_latency = 19
      local proxy_latency = 980
      local request_size = 102400
      local response_size = 409600
      local statuses = {}
      local xcount = 99
      local xpl = 900
      local xreqs = 100000
      local xresps = 400000
      statuses["200"] = {count = xcount, proxy_latency = xpl, request_size = xreqs, response_size=xresps}
      local ycount = 1
      local ypl = 80
      local yreqs = 2400
      local yresps = 9600
      statuses["500"] = {count = ycount, proxy_latency = ypl, request_size = yreqs, response_size = yresps}
      local expected = fmt("%d,%d,%d,%d,%d,%d,", request_count, request_latency, kong_latency, proxy_latency,
                           request_size, response_size)
      expected = expected .. fmt("200:%d:%d:%d:%d,", xcount, xpl, xreqs, xresps)
      expected = expected .. fmt("500:%d:%d:%d:%d", ycount, ypl, yreqs, yresps)
      local encoded = handler:encode_metrics(request_count, request_latency, kong_latency, proxy_latency,
                                             request_size, response_size, statuses)
      assert.equal(encoded, expected)
    end)

    it("Decodes metric strings as expected", function()
      local encoded = "300,6000,78,1980,152413,629660,204:29:600:3000:0,301:1:180:1706:602,405:11:835:99:100"
      local ex_request_count = 300
      local ex_request_latency = 6000
      local ex_kong_latency = 78
      local ex_proxy_latency = 1980
      local ex_request_size = 152413
      local ex_response_size = 629660
      local ex_statuses = {}
      ex_statuses["204"] = {count = 29, proxy_latency = 600, request_size = 3000, response_size = 0}
      ex_statuses["301"] = {count = 1, proxy_latency = 180, request_size = 1706, response_size = 602}
      ex_statuses["405"] = {count = 11, proxy_latency = 835, request_size = 99, response_size = 100}
      local request_count, request_latency, kong_latency, proxy_latency, request_size, response_size,
            statuses = handler:decode_metrics(encoded)
      assert.equal(request_count, ex_request_count)
      assert.equal(request_latency, ex_request_latency)
      assert.equal(kong_latency, ex_kong_latency)
      assert.equal(proxy_latency, ex_proxy_latency)
      assert.equal(request_size, ex_request_size)
      assert.equal(response_size, ex_response_size)
      assert.are.same(statuses, ex_statuses)
    end)
  end)
end)
