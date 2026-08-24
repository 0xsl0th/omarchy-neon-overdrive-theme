local active_border = {
  colors = { "rgba(00f5ffff)", "rgba(ff2bd6ff)" },
  angle = 45,
}

local inactive_border = {
  colors = { "rgba(43245e99)", "rgba(00f5ff55)" },
  angle = 45,
}

hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 12,
    border_size = 3,
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },

  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
  },

  decoration = {
    rounding = 12,
    rounding_power = 2,
    dim_inactive = true,
    dim_strength = 0.08,
    shadow = {
      enabled = true,
      range = 18,
      render_power = 3,
      color = "rgba(ff2bd699)",
      color_inactive = "rgba(00f5ff28)",
    },
    blur = {
      enabled = true,
      size = 8,
      passes = 3,
    },
  },

  animations = {
    enabled = true,
  },
})

hl.curve("neonSnap", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("neonGlide", { type = "bezier", points = { { 0.45, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "neonGlide" })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "neonSnap" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "neonSnap", style = "popin 88%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "neonGlide", style = "popin 88%" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "neonGlide" })
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "neonGlide" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "neonGlide", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "neonSnap", style = "slidevert" })
