##### Requirements: 
- [lux_library](https://github.com/LuxLuma/Lux-Library/tree/master/scripting/include) include to compile. 
- [DHooks (Experimental Dynamic Detour support)](https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589) 



#### Convars  
````
// Acid attack interval
// -
// Default: "0.1"
bb_acid_attack_interval "0.1"

// Acid attack interval survivors
// -
// Default: "0.1"
bb_acid_attack_interval_survivor "0.1"

// Acid attack percent max health damage to deal per interval (min 1 damage regardless)
// -
// Default: "0.006"
bb_acid_damage_percent "0.006"

// Acid attack percent max health damage to deal per interval survivor (min 1 damage regardless)
// -
// Default: "0.0"
bb_acid_damage_percent_survivor "0.0"

// Sound emit interval for acid attack
// -
// Default: "0.5"
bb_acid_hit_sound_interval "0.5"

// Acid effect life time
// -
// Default: "15.0"
bb_acid_life "15.0"

// Acid effect life time survivors
// -
// Default: "3.0"
bb_acid_life_survivor "3.0"

// Update interval to try spawning a acid pool(Visual only) does not deal damage
// -
// Default: "0.1"
bb_acid_pool_update_interval "0.1"

// Cannot be broken on impacts for set time after spawning, stationery bile bombs will not break without help
// -
// Default: "0.2"
// Maximum: "0.500000"
bb_vomitjar_break_immunity_time "0.2"

// Vomitjar bile radius
// -
// Default: "200.0"
bb_vomitjar_radius "200.0"

// vomitjar bile radius survivors, only affects thrower
// -
// Default: "100.0"
bb_vomitjar_radius_survivor "100.0"
````
#### Acid pool preview
![](https://raw.githubusercontent.com/LuxLuma/L4D2_Bile_bomb_rework/master/acid_trail.gif)
