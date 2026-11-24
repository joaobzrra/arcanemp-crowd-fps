local DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""; dofile(DIR .. "ticklod_impl.lua"); CrowdTickLodOff(5)
