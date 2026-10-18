-- DEV ONLY (never upload). Organic Towns dev tools HUD button registration, as the probe's otp_hud.res.lua:
-- extension point "::MainModButtonAreaExtension" (base gui/main/main_mod_button_area.tl). Adds a plugin.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_organic_towns_dev::/organic_towns_dev/otd_hud.script@OtdHudPlugin",
			order = 98,
		}
	}
end
