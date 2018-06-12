std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = false

files["spec/**/*.lua"] = {
    std = "ngx_lua+busted",
}
