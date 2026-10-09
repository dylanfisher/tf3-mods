-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## Hawaii") instead of here. Plain ASCII throughout: okina and
-- kahako dropped (Kalākaua -> Kalakaua, Kaʻahumanu -> Kaahumanu), as in the Census town names.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name inside the town's Census
--                  (CDP) boundary relation (Hawaii has no city boundaries below the county), directional prefix
--                  dropped ("South King Street" ships as "King Street") except where it is part of the name
--                  (South/North Kihei Road, Lower Main Street).
--   neighborhoods  bus/tram stations. Honolulu: the City and County of Honolulu "Neighborhoods" GIS layer
--                  (services.arcgis.com tNJpAOha4mODLkXz, AdministrativePolitical layer 0, 2026-10-08), only names
--                  whose point falls inside the Urban Honolulu CDP ("Kam Heights" ships as Kamehameha Heights,
--                  the neighbourhood board's spelling). East Honolulu: the same layer, names inside the East
--                  Honolulu CDP (Hawaii Kai, Aina Haina, ...).
--   rail           passenger train stations, WITHOUT a trailing "Station". Skyline, the 13 open stations (TheBus/DTS
--                  GTFS 2608_v5, route 181; names from honolulu.gov/dts/skyline). Official names pair a Hawaiian and
--                  an English name ("Kahauiki, Kalihi Transit Center Station"); the English half ships, except
--                  Kualakai (its English half, East Kapolei, is a town). Halaulani/Leeward Community College sits
--                  in no CDP and is keyed to Pearl City next door. Left out (data_review): Makalapa (no CDP) and
--                  the airport station (the airport entry carries the name).
--   airport        airports/airfields: FAA names (NASR APT_BASE, cycle 2026-10-01) in the short form the state
--                  uses on airports.hawaii.gov: Daniel K. Inouye International Airport (Honolulu), Kona
--                  International Airport (the full "Ellison Onizuka Kona International Airport at Keahole" is over
--                  40 bytes), Waimea-Kohala Airport (FAA city Kamuela = Waimea), Kawaihapai Airfield (formerly
--                  Dillingham Airfield, Mokuleia), Kapalua Airport keyed to Kapalua.
--   harbor         passenger terminals in use: Maalaea Harbor and Manele Harbor (the Expeditions Maui-Lanai ferry,
--                  go-lanai.com; it moved from Lahaina after the 2023 fire), the Pier 2 Cruise Ship Terminal
--                  (HDOT Harbors, Honolulu Harbor) and Kailua Pier (the Kona cruise tender landing; DLNR "Kailua-Kona
--                  Wharf").
-- Station names are unique map-wide; street names are unique per town.
return {
	["Honolulu"] = {
		streets = {
			"Kalakaua Avenue", "Ala Moana Boulevard", "Kapiolani Boulevard", "King Street", "Beretania Street",
			"Nimitz Highway", "Pali Highway", "Likelike Highway", "Kalanianaole Highway", "Waialae Avenue", "Kapahulu Avenue",
			"University Avenue", "Ward Avenue", "Nuuanu Avenue", "Punchbowl Street", "Bishop Street", "Fort Street",
			"Alakea Street", "Queen Street", "Hotel Street", "Merchant Street", "Maunakea Street", "Dillingham Boulevard",
			"Kuhio Avenue", "Ala Wai Boulevard", "Lewers Street", "Keeaumoku Street", "Piikoi Street", "McCully Street",
			"Liliha Street", "School Street", "Vineyard Boulevard", "Monsarrat Avenue", "Diamond Head Road", "Kahala Avenue",
			"Dole Street", "Manoa Road", "Punahou Street", "Kaimuki Avenue", "Salt Lake Boulevard",
		},
		neighborhoods = {
			"Waikiki", "Kaimuki", "Manoa", "Makiki", "Moiliili", "McCully", "Kakaako", "Chinatown", "Downtown", "Kalihi",
			"Palama", "Kapalama", "Nuuanu", "Pauoa", "Liliha", "Puunui", "Alewa Heights", "Kamehameha Heights", "Punchbowl",
			"Papakolea", "Tantalus", "Pacific Heights", "Makiki Heights", "Ala Moana", "Kapahulu", "Diamond Head",
			"Black Point", "Kahala", "Palolo", "St. Louis Heights", "Maunalani Heights", "Wilhelmina", "Moanalua",
			"Salt Lake", "Aliamanu", "Mapunapuna", "Pawaa", "Punahou", "Woodlawn", "Kalihi Valley", "Sand Island",
		},
		rail = {
			"Lagoon Drive", "Kalihi Transit Center",
		},
		airport = {
			"Daniel K. Inouye International Airport",
		},
		harbor = {
			"Pier 2 Cruise Ship Terminal",
		},
	},
	["Hilo"] = {
		streets = {
			"Kamehameha Avenue", "Kanoelehua Avenue", "Kilauea Avenue", "Keawe Street", "Waianuenue Avenue", "Kinoole Street",
			"Banyan Drive", "Bayfront Highway", "Puainako Street", "Komohana Street", "Kaumana Drive", "Ponahawai Street",
			"Kapiolani Street", "Haili Street", "Mamo Street", "Kalanianaole Street", "Railroad Avenue", "Kekuanaoa Street",
			"Mohouli Street", "Makaala Street", "Ainaola Drive", "Wilder Road", "Lihiwai Street", "Pauahi Street",
			"Manono Street", "Kukuau Street", "Wainaku Avenue", "Kalakaua Street", "Aupuni Street", "Mamalahoa Highway",
		},
		airport = {
			"Hilo International Airport",
		},
	},
	["Kailua-Kona"] = {
		streets = {
			"Alii Drive", "Palani Road", "Kuakini Highway", "Queen Kaahumanu Highway", "Henry Street", "Hualalai Road",
			"Makala Boulevard", "Kealakehe Parkway", "Walua Road", "Kamakaeha Avenue", "Kopiko Street", "Hale Kapili Street",
			"Sarona Road", "Luhia Street", "Kalani Street", "Kaiwi Street", "Kealakaa Street", "Alapa Street", "Kahakai Road",
			"Mamalahoa Highway", "Malulani Street", "Keanalehu Drive", "Kona Bay Drive",
		},
		airport = {
			"Kona International Airport",
		},
		harbor = {
			"Kailua Pier",
		},
	},
	["Kahului"] = {
		streets = {
			"Kaahumanu Avenue", "Hana Highway", "Puunene Avenue", "Dairy Road", "Kahului Beach Road", "Haleakala Highway",
			"Kamehameha Avenue", "Wakea Avenue", "Hobron Avenue", "Kuihelani Highway", "Maui Lani Parkway", "Hookele Street",
			"Onehee Avenue", "Papa Avenue", "Lono Avenue", "Kane Street", "Wharf Street", "Hina Avenue", "Kanaloa Avenue",
			"Pakaula Street", "Alamaha Street", "Hansen Road", "Pulehu Road", "Keolani Place",
		},
		airport = {
			"Kahului Airport",
		},
	},
	["Wailuku"] = {
		streets = {
			"Main Street", "Market Street", "High Street", "Vineyard Street", "Iao Valley Road", "Lower Main Street",
			"Mill Street", "Wells Street", "Kaahumanu Avenue", "Waiehu Beach Road", "Honoapiilani Highway",
			"Kahekili Highway", "Kuikahi Drive", "Waiale Road", "Alu Road", "Church Street", "Mission Street",
			"Central Avenue", "Kehalani Mauka Parkway", "Kaniela Street", "Kahookele Street",
		},
	},
	["Lahaina"] = {
		streets = {
			"Front Street", "Honoapiilani Highway", "Lahainaluna Road", "Wainee Street", "Dickenson Street", "Prison Street",
			"Shaw Street", "Keawe Street", "Kenui Street", "Papalaua Street", "Baker Street", "Mill Street", "Wahikuli Road",
			"Kapunakea Street", "Kuhua Street", "Leialii Parkway", "Fleming Road", "Lahaina Bypass", "Civic Center Drive",
		},
	},
	["Lihue"] = {
		streets = {
			"Rice Street", "Kuhio Highway", "Kaumualii Highway", "Ahukini Road", "Kapule Highway", "Nawiliwili Road",
			"Hardy Street", "Haleko Road", "Kress Street", "Umi Street", "Hoolako Street", "Kalena Street", "Elua Street",
			"Akahi Street", "Waapa Road", "Niumalu Road", "Kapaia Road", "Pikake Street", "Kanoa Road", "Maalo Road",
		},
		airport = {
			"Lihue Airport",
		},
	},
	["Kailua"] = {
		streets = {
			"Kailua Road", "Oneawa Street", "Kalaheo Avenue", "Kuulei Road", "Hamakua Drive", "Keolu Drive",
			"Mokapu Boulevard", "Kaneohe Bay Drive", "Kalanianaole Highway", "Aalapapa Drive", "Mokulua Drive", "Wanaao Road",
			"Hahani Street", "Kihapai Street", "Aulike Street", "Uluniu Street", "Hekili Street", "Hoolai Street",
			"Kainui Drive", "Aikahi Loop", "Kawailoa Road", "Awakea Road", "Alala Road", "Kainalu Drive", "Maluniu Avenue",
		},
	},
	["Kaneohe"] = {
		streets = {
			"Kamehameha Highway", "Kaneohe Bay Drive", "Likelike Highway", "Kahekili Highway", "Kahuhipa Street",
			"Mokapu Road", "Keaahala Road", "Puohala Street", "Lilipuna Road", "Luluku Road", "Anoi Road", "Namoku Street",
			"Waikalua Road", "Apapane Street", "Kokokahi Place", "Mokulele Drive", "Pookela Street", "Alaloa Street",
			"Kapunahala Road", "Wailele Road",
		},
	},
	["Pearl City"] = {
		streets = {
			"Kamehameha Highway", "Moanalua Road", "Waimano Home Road", "Kuala Street", "Komo Mai Drive", "Acacia Road",
			"Lehua Avenue", "Hoolaulea Street", "Noelani Street", "Waihona Street", "Hoomalu Street", "Puu Poni Street",
			"Waiawa Road", "Aloha Avenue", "Lanakila Avenue", "Palm Avenue", "Franklin Avenue", "Hoohulu Street",
			"2nd Street", "3rd Street",
		},
		rail = {
			"Pearl Highlands", "Leeward Community College",
		},
	},
	["Kapolei"] = {
		streets = {
			"Kapolei Parkway", "Farrington Highway", "Kamokila Boulevard", "Wakea Street", "Kalaeloa Boulevard",
			"Fort Barrette Road", "Kualakai Parkway", "Hoomohala Avenue", "Kamaaha Avenue", "Kuloa Avenue", "Kaiau Avenue",
			"Kinoiki Street", "Makakilo Drive", "Keahumoa Parkway", "Haumea Street", "Manawai Street", "Kunehi Street",
			"Uluohia Street", "Alohikea Street", "Kealanani Avenue",
		},
		airport = {
			"Kalaeloa Airport",
		},
	},
	["Kihei"] = {
		streets = {
			"Piilani Highway", "South Kihei Road", "North Kihei Road", "Lipoa Parkway", "Piikea Avenue", "Ohukai Road",
			"Kulanihakoi Street", "Uwapo Road", "Kenolio Road", "Welakahao Road", "Alanui Kealii", "Kanani Road",
			"Liloa Drive", "Waipuilani Road", "Lipoa Street", "Kaonoulu Street", "Maui Veterans Highway", "Halekuai Street",
			"Auhana Road", "Kanakanui Road",
		},
	},
	["Kapaa"] = {
		streets = {
			"Kuhio Highway", "Kawaihau Road", "Kukui Street", "Mailihuna Road", "Kapaa Bypass", "Olohena Road",
			"Hauaala Road", "Kaehulua Road", "Malu Road", "Hauiki Road", "Kainahola Road", "Keaka Road", "Kipuni Street",
			"Ulu Street", "Lehua Street", "Niu Street", "Huluili Street",
		},
	},
	["East Honolulu"] = {
		neighborhoods = {
			"Hawaii Kai", "Aina Haina", "Niu Valley", "Kuliouou", "Kalani Iki", "Waialae Iki", "Hawaii Loa Ridge", "Portlock",
			"Kalama Valley", "Koko Head",
		},
	},
	["East Kapolei"] = {
		rail = {
			"Kualakai", "University of Hawaii West Oahu", "Hoopili",
		},
	},
	["Waipahu"] = {
		rail = {
			"West Loch", "Waipahu Transit Center",
		},
	},
	["Waimalu"] = {
		rail = {
			"Pearlridge",
		},
	},
	["Halawa"] = {
		rail = {
			"Aloha Stadium",
		},
	},
	["Kaunakakai"] = {
		airport = {
			"Molokai Airport",
		},
	},
	["Lanai City"] = {
		airport = {
			"Lanai Airport",
		},
		harbor = {
			"Manele Harbor",
		},
	},
	["Kapalua"] = {
		airport = {
			"Kapalua Airport",
		},
	},
	["Hana"] = {
		airport = {
			"Hana Airport",
		},
	},
	["Waimea"] = {
		airport = {
			"Waimea-Kohala Airport",
		},
	},
	["Hawi"] = {
		airport = {
			"Upolu Airport",
		},
	},
	["Mokuleia"] = {
		airport = {
			"Kawaihapai Airfield",
		},
	},
	["Hanapepe"] = {
		airport = {
			"Port Allen Airport",
		},
	},
	["Maalaea"] = {
		harbor = {
			"Maalaea Harbor",
		},
	},
}
