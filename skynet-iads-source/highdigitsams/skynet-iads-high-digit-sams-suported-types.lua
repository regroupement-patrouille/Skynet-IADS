do
-- this file contains the definitions for the HightDigitSAMSs: https://github.com/Auranis/HighDigitSAMs

--[[ units in SA-10 group Gargoyle:
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 54K6 cp
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 5P85CE ln
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 5P85DE ln
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 40B6MD sr
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 64N6E sr
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 40B6M tr
2020-12-10 18:27:27.050 INFO    SCRIPTING: S-300PMU1 30N6E tr
--]]
s3000pmu1 = {
	['type'] = 'complex',
	['searchRadar'] = {
		['S-300PMU1 40B6MD sr'] = {
		},
		['S-300PMU1 64N6E sr'] = {
		},
	},
	['trackingRadar'] = {
		['S-300PMU1 40B6M tr'] = {
		},
		['S-300PMU1 30N6E tr'] = {
		},
	},
	['misc'] = {
		['S-300PMU1 54K6 cp'] = {
			['required'] = true,
		},
	},
	['launchers'] = {
		['S-300PMU1 5P85CE ln'] = {
		},
		['S-300PMU1 5P85DE ln'] = {
		},
	},
	['name']  = {
		['NATO'] = 'SA-20A Gargoyle'
	},
	['harm_detection_chance'] = 90
}	
samTypesDB['S-300PMU1'] = s3000pmu1

--[[ Units in the SA-23 Group:
2020-12-11 16:40:52.072 INFO    SCRIPTING: S-300VM 9A82ME ln
2020-12-11 16:40:52.072 INFO    SCRIPTING: S-300VM 9A83ME ln
2020-12-11 16:40:52.072 INFO    SCRIPTING: S-300VM 9S15M2 sr
2020-12-11 16:40:52.072 INFO    SCRIPTING: S-300VM 9S19M2 sr
2020-12-11 16:40:52.072 INFO    SCRIPTING: S-300VM 9S32ME tr
2020-12-11 16:40:52.072 INFO    SCRIPTING: S-300VM 9S457ME cp

According to wikipedia:
dem 9A83-Startfahrzeug die Bezeichnung SA-12A Gladiator zu geben; das größere 9A82-Startfahrzeug erhielt die Bezeichnung SA-12B Giant.
9A83ME -> SA-23A Gladiator
9A82ME -> SA-23B Giant
]]--
s300vm = {
	['type'] = 'complex',
	['searchRadar'] = {
		['S-300VM 9S15M2 sr'] = {
		},
		['S-300VM 9S19M2 sr'] = {
		},
	},
	['trackingRadar'] = {
		['S-300VM 9S32ME tr'] = {
		},
	},
	['misc'] = {
		['S-300VM 9S457ME cp'] = {
			['required'] = true,
		},
	},
	['launchers'] = {
		['S-300VM 9A82ME ln'] = {
		},
		['S-300VM 9A83ME ln'] = {
		},
	},
	['name']  = {
		['NATO'] = 'SA-23 Gladiator/Giant'
	},
	['harm_detection_chance'] = 90
}	
samTypesDB['S-300VM'] = s300vm
end