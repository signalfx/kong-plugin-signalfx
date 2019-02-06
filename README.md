# SignalFx Kong Plugin
This [Kong plugin](https://getkong.org/docs/0.13.x/admin-api/#plugin-object) is intended for SignalFx users to obtain
performance metrics from their Kong deployments for aggregation and reporting via the
[Smart Agent](https://github.com/signalfx/signalfx-agent) or the
[collectd-kong](https://github.com/signalfx/collectd-kong) collectd plugin.  It works similarly to other Kong logging
plugins and provides connection state and request/response count, latency, status, and size metrics available through
a `/signalfx` Admin API endpoint.

### Installation
To install this plugin from its source repository, run the following on each Kong server with a
properly configured `LUA_PATH`:
```sh
luarocks install kong-plugin-signalfx
# or directly from the source repo
git clone git@github.com:signalfx/kong-plugin-signalfx.git
cd kong-plugin-signalfx
luarocks make

# and be sure to notify Kong of the plugin

echo 'custom_plugins = signalfx' > /etc/kong/signalfx.conf  # or add to your existing configuration file
```

The following [lua_shared_dict](https://github.com/openresty/lua-nginx-module#lua_shared_dict) memory declarations
will need to be made in your Kong's nginx configuration file or can be added directly to
`/usr/local/share/lua/5.1/kong/templates/nginx_kong.lua` (or its actual location on your system) if you are using
Kong's default setup.
```
lua_shared_dict kong_signalfx_aggregation 10m;
lua_shared_dict kong_signalfx_locks 100k;
```

Reload Kong to make the plugin available and (if desired) install it globally:
```sh
kong reload -c /etc/kong/signalfx.conf  # or specify your modified configuration file
curl -X POST -d "name=signalfx" http://localhost:8001/plugins
```

### Configuration
Like most Kong plugins, the SignalFx plugin can be configured globally or by specific Service, Route, API, and
Consumer object contexts by making `POST` requests to each desired Kong object's related `plugins` endpoint.

```sh
curl -X POST -d "name=signalfx" http://localhost:8001/services/MyService/plugins
curl -X POST -d "name=signalfx" http://localhost:8001/routes/<my_route_id>/plugins
```

For each request made to the respective registered object context, metric content will be obtained and aggregated for
automated retrieval at the `/signalfx` endpoint of the Admin API.  Though request contexts can be enabled for
specific Consumer objects, please note that Consumer ID's or unique visitor metrics are not calculated at this time.

By default, metrics for each Service/API-fielded request cycle will be aggregated by a context determined partially
by the request's HTTP method and by its response's status code.  If you are monitoring a large infrastructure with
hundreds of routes, grouping by HTTP method can be too granular or costly for performant `/signalfx` requests on a 1s
interval, depending on the server resources.  This context grouping can be disabled with the boolean configuration
option `aggregate_by_http_method`.

```sh
curl -X POST -d "name=signalfx" -d "config.aggregate_by_http_method=false" http://localhost:8001/plugins
# or to edit an existing plugin
curl -X PATCH -d "config.aggregate_by_http_method=false" http://localhost:8001/plugins/<sfx_plugin_id>
```
