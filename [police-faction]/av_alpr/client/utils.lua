local colors = {
	['0'] = "Black", ['1'] = "Graphite", ['2'] = "Black Steel", ['3'] = "Dark Silver", ['4'] = "Silver", ['5'] = "Blue Silver", ['6'] = "Steel Gray", ['7'] = "Shadow Silver", ['8'] = "Stone Silver", ['9'] = "Midnight Silver",
	['10'] = "Gun Metal", ['11'] = "Anthracite Gray", ['12'] = "Matte Black", ['13'] = "Matte Gray", ['14'] = "Light Gray", ['15'] = "Util Black", ['16'] = "Util Black Poly", ['17'] = "Util Dark Silver", ['18'] = "Util Silver", ['19'] = "Util Gun Metal",
	['20'] = "Shadow Silver", ['21'] = "Black", ['22'] = "Graphite", ['23'] = "Silver Gray", ['24'] = "Silver", ['25'] = "Blue Silver", ['26'] = "Shadow Silver", ['27'] = "Red", ['28'] = "Torino Red", ['29'] = "Formula Red",
	['30'] = "Blaze Red", ['31'] = "Graceful Red", ['32'] = "Garnet Red", ['33'] = "Desert Red", ['34'] = "Cabernet Red", ['35'] = "Candy Red", ['36'] = "Sunrise Orange", ['37'] = "Classic Gold", ['38'] = "Orange", ['39'] = "Matte Red",
	['40'] = "Dark Red", ['41'] = "Matte Orange", ['42'] = "Matte Yellow", ['43'] = "Util Red", ['44'] = "Util Bright Red", ['45'] = "Util Garnet Red", ['46'] = "Red", ['47'] = "Golden Red", ['48'] = "Dark Red", ['49'] = "Dark Green",
	['50'] = "Racing Green", ['51'] = "Sea Green", ['52'] = "Olive Green", ['53'] = "Green", ['54'] = "Gasoline Blue Green", ['55'] = "Lime Green", ['56'] = "Dark Green", ['57'] = "Green", ['58'] = "Dark Green", ['59'] = "Green",
	['60'] = "Sea Wash", ['61'] = "Midnight Blue", ['62'] = "Dark Blue", ['63'] = "Saxony Blue", ['64'] = "Blue", ['65'] = "Mariner Blue", ['66'] = "Harbor Blue", ['67'] = "Diamond Blue", ['68'] = "Surf Blue", ['69'] = "Nautical Blue",
	['70'] = "Bright Blue", ['71'] = "Purple Blue", ['72'] = "Spinnaker Blue", ['73'] = "Ultra Blue", ['74'] = "Bright Blue", ['75'] = "Dark Blue", ['76'] = "Midnight Blue", ['77'] = "Blue", ['78'] = "Sea Foam Blue", ['79'] = "Lightning Blue",
	['80'] = "Maui Blue Poly", ['81'] = "Bright Blue", ['82'] = "Matte Dark Blue", ['83'] = "Matte Blue", ['84'] = "Matte Midnight Blue", ['85'] = "Util Dark Blue", ['86'] = "Util Blue", ['87'] = "Util Midnight Blue", ['88'] = "Yellow", ['89'] = "Race Yellow",
	['90'] = "Bronze", ['91'] = "Yellow Bird", ['92'] = "Lime", ['93'] = "Champagne", ['94'] = "Pueblo Beige", ['95'] = "Dark Ivory", ['96'] = "Choco Brown", ['97'] = "Golden Brown", ['98'] = "Light Brown", ['99'] = "Straw Beige",
	['100'] = "Moss Brown", ['101'] = "Biston Brown", ['102'] = "Beechwood", ['103'] = "Dark Beechwood", ['104'] = "Choco Orange", ['105'] = "Beach Sand", ['106'] = "Sun Bleeched Sand", ['107'] = "Cream", ['108'] = "Brown", ['109'] = "Medium Brown",
	['110'] = "Pale Brown", ['111'] = "Metallic White", ['112'] = "White", ['113'] = "Worn White", ['114'] = "Brown", ['115'] = "Dark Brown", ['116'] = "Beige", ['117'] = "Steel", ['118'] = "Black Steel", ['119'] = "Aluminium",
	['120'] = "Chrome", ['121'] = "Worn Off White", ['122'] = "Util Off White", ['123'] = "Orange", ['124'] = "Light Orange", ['125'] = "Sec Green", ['126'] = "Taxi Yellow", ['127'] = "Police Blue", ['128'] = "Green", ['129'] = "Matte Brown",
	['130'] = "Orange", ['131'] = "Matte White", ['132'] = "White", ['133'] = "Olive Army Green", ['134'] = "Pure White", ['135'] = "Hot Pink", ['136'] = "Salmon pink", ['137'] = "Pfister Pink", ['138'] = "Orange", ['139'] = "Green",
	['140'] = "Blue", ['141'] = "Mettalic Black Blue", ['142'] = "Metallic Black Purple", ['143'] = "Metallic Black Red", ['144'] = "Hunter Green", ['145'] = "Metallic Purple", ['146'] = "Metaillic V Dark Blue", ['147'] = "Modshop Black1", ['148'] = "Matte Purple", ['149'] = "Matte Dark Purple",
	['150'] = "Metallic Lava Red", ['151'] = "Matte Forest Green", ['152'] = "Matte Olive Drab", ['153'] = "Matte Desert Brown", ['154'] = "Matte Desert Tan", ['155'] = "Matte Foilage Green", ['156'] = "Default Alloy Color", ['157'] = "Epsilon Blue", ['158'] = "Pure Gold", ['159'] = "Brushed Gold",
	['160'] = "Light Blue"
}

function GetColorName(id)
	return colors[tostring(id)] or "Unknown"
end