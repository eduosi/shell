local command = "/usr/local/GraphicsMagick/bin/gm convert " .. ngx.var.request_filepath .. " -thumbnail \"" .. ngx.var.width .. "x" .. ngx.var.height .. ">\" +profile \"*\" " .. ngx.var.request_filepath .. "_" .. ngx.var.width .. "x" .. ngx.var.height .. "." .. ngx.var.ext;
os.execute(command);
ngx.req.set_uri(ngx.var.request_uri, true);