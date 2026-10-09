-- Generic Hawaii-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common Hawaiian street patterns: everyday Hawaiian words (mauka/makai, kai, lani, aloha, ohana), native
-- and island plants and birds, plantation-era names and numbered streets. Every Hawaiian word here is in use
-- as a street name in at least one of the 13 Overpass-checked towns (2026-10-08). Plain ASCII: okina and
-- kahako dropped, as on most street signs. Not tied to any one real town; keep each name <= 40 bytes.
return {
	-- core and plantation
	"Main Street", "Front Street", "Market Street", "Church Street", "School Street", "Mill Street", "Pier Street",
	"Beach Road", "Camp Road", "Plantation Road", "Railroad Avenue", "Park Avenue", "Ranch Road", "Cane Haul Road",
	"Sugar Mill Road", "Pineapple Road", "Paniolo Drive", "Kamehameha Avenue",
	-- numbered and lettered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Avenue", "7th Avenue",
	"10th Avenue", "A Street", "B Street", "C Street",
	-- directions, land and sea
	"Mauka Road", "Makai Road", "Kai Street", "Kai Drive", "Moana Street", "Kahakai Drive", "Kuahiwi Avenue",
	"Puu Road", "Pali Road", "Kahawai Street", "Wai Street", "Waiola Street", "Muliwai Road", "Lae Street",
	"Kula Road", "Mala Street", "Loi Road", "Pohaku Street", "Kipuka Street", "Pahoehoe Street", "Hono Street",
	"Awa Street", "Uka Street", "Reef Road", "Lagoon Drive", "Coral Street", "Harbor Road", "Surf Road",
	"Sunset Road", "Lava Road", "Crater Road",
	-- sky and weather
	"Lani Street", "Hoku Street", "Mahina Avenue", "Anuenue Street", "Makani Avenue", "Kehau Street",
	"Kilohana Street", "Ao Street", "Ua Road", "Malu Road",
	-- words of welcome
	"Aloha Street", "Aloha Avenue", "Ohana Street", "Pono Street", "Lokahi Street", "Malama Street", "Nani Street",
	"Hale Street", "Hoolaulea Street", "Lanakila Avenue", "Leilani Street", "Noelani Street", "Iwalani Street",
	"Mililani Street",
	-- flowers and trees
	"Plumeria Street", "Hibiscus Drive", "Ilima Street", "Lehua Avenue", "Ohia Street", "Koa Avenue",
	"Kukui Street", "Hala Drive", "Lauhala Street", "Niu Street", "Ulu Street", "Mango Street", "Papaya Road",
	"Banyan Drive", "Kiawe Street", "Naupaka Street", "Maile Way", "Pikake Street", "Gardenia Street",
	"Orchid Street", "Kalo Street", "Mamane Street", "Wiliwili Street", "Kamani Street", "Milo Street",
	"Hau Street", "Awapuhi Street", "Poinciana Street", "Acacia Road", "Palm Avenue",
	-- birds and sea life
	"Nene Street", "Iiwi Street", "Apapane Street", "Elepaio Street", "Kolea Street", "Pueo Street", "Alae Street",
	"Manu Street", "Moa Street",
}
