local DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""; dofile(DIR .. "farint_impl.lua"); CrowdFarInterval(50, 0.2)
