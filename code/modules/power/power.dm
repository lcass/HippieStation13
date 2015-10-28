//////////////////////////////
// POWER MACHINERY BASE CLASS
//////////////////////////////

/////////////////////////////
// Definitions
/////////////////////////////

/obj/machinery/power
	name = null
	icon = 'icons/obj/power.dmi'
	anchored = 1
	var/datum/powernet/powernet = null
	use_power = 0
	idle_power_usage = 0
	active_power_usage = 0
	var/max_voltage = 1000//max it out so nothing splodes under normal use.

/obj/machinery/power/Destroy()
	disconnect_from_network()
	return ..()

///////////////////////////////
// General procedures
//////////////////////////////

// common helper procs for all power machines
/obj/machinery/power/proc/add_avail(amount,var/voltage = 5000)
	if(powernet)
		powernet.add_avail(amount,voltage)

/obj/machinery/power/proc/add_load(amount)
	if(powernet)
		powernet.load += amount

/obj/machinery/power/proc/surplus()
	if(powernet)
		return powernet.avail-powernet.load
	else
		return 0

/obj/machinery/power/proc/avail()
	if(powernet)
		return powernet.avail
	else
		return 0

/obj/machinery/power/proc/disconnect_terminal() // machines without a terminal will just return, no harm no fowl.
	return

// returns true if the area has power on given channel (or doesn't require power).
// defaults to power_channel
/obj/machinery/proc/powered(var/chan = -1) // defaults to power_channel

	if(!src.loc)
		return 0

	if(!use_power)
		return 1

	var/area/A = src.loc.loc		// make sure it's in an area
	if(!A || !isarea(A) || !A.master)
		return 0					// if not, then not powered
	if(chan == -1)
		chan = power_channel
	return A.master.powered(chan)	// return power status of the area

// increment the power usage stats for an area
/obj/machinery/proc/use_power(amount, chan = -1) // defaults to power_channel
	var/area/A = get_area(src)		// make sure it's in an area
	if(!A || !isarea(A) || !A.master)
		return
	if(chan == -1)
		chan = power_channel
	A.master.use_power(amount, chan)

/obj/machinery/proc/addStaticPower(value, powerchannel)
	var/area/A = get_area(src)
	if(!A || !A.master)
		return
	A.master.addStaticPower(value, powerchannel)

/obj/machinery/proc/removeStaticPower(value, powerchannel)
	addStaticPower(-value, powerchannel)

/obj/machinery/proc/power_change()		// called whenever the power settings of the containing area change
										// by default, check equipment channel & set flag
										// can override if needed
	if(powered(power_channel))
		stat &= ~NOPOWER
	else

		stat |= NOPOWER
	return

// connect the machine to a powernet if a node cable is present on the turf
/obj/machinery/power/proc/connect_to_network()
	var/turf/T = src.loc
	if(!T || !istype(T))
		return 0

	var/obj/structure/cable/C = T.get_cable_node() //check if we have a node cable on the machine turf, the first found is picked
	if(!C || !C.powernet)
		return 0

	C.powernet.add_machine(src)
	return 1

// remove and disconnect the machine from its current powernet
/obj/machinery/power/proc/disconnect_from_network()
	if(!powernet)
		return 0
	powernet.remove_machine(src)
	return 1

// attach a wire to a power machine - leads from the turf you are standing on
//almost never called, overwritten by all power machines but terminal and generator
/obj/machinery/power/attackby(obj/item/weapon/W, mob/user, params)

	if(istype(W, /obj/item/stack/cable_coil))

		var/obj/item/stack/cable_coil/coil = W

		var/turf/T = user.loc

		if(T.intact || !istype(T, /turf/simulated/floor))
			return

		if(get_dist(src, user) > 1)
			return

		coil.place_turf(T, user)
		return
	else
		..()
	return

///////////////////////////////////////////
// Powernet handling helpers
//////////////////////////////////////////

//returns all the cables WITHOUT a powernet in neighbors turfs,
//pointing towards the turf the machine is located at
/obj/machinery/power/proc/get_connections()

	. = list()

	var/cdir
	var/turf/T

	for(var/card in cardinal)
		T = get_step(loc,card)
		cdir = get_dir(T,loc)

		for(var/obj/structure/cable/C in T)
			if(C.powernet)	continue
			if(C.d1 == cdir || C.d2 == cdir)
				. += C
	return .

//returns all the cables in neighbors turfs,
//pointing towards the turf the machine is located at
/obj/machinery/power/proc/get_marked_connections()

	. = list()

	var/cdir
	var/turf/T

	for(var/card in cardinal)
		T = get_step(loc,card)
		cdir = get_dir(T,loc)

		for(var/obj/structure/cable/C in T)
			if(C.d1 == cdir || C.d2 == cdir)
				. += C
	return .

//returns all the NODES (O-X) cables WITHOUT a powernet in the turf the machine is located at
/obj/machinery/power/proc/get_indirect_connections()
	. = list()
	for(var/obj/structure/cable/C in loc)
		if(C.powernet)	continue
		if(C.d1 == 0) // the cable is a node cable
			. += C
	return .

///////////////////////////////////////////
// GLOBAL PROCS for powernets handling
//////////////////////////////////////////


// returns a list of all power-related objects (nodes, cable, junctions) in turf,
// excluding source, that match the direction d
// if unmarked==1, only return those with no powernet
/proc/power_list(turf/T, source, d, unmarked=0, cable_only = 0)
	. = list()
	//var/fdir = (!d)? 0 : turn(d, 180)			// the opposite direction to d (or 0 if d==0)

	for(var/AM in T)
		if(AM == source)	continue			//we don't want to return source

		if(!cable_only && istype(AM,/obj/machinery/power))
			var/obj/machinery/power/P = AM
			if(P.powernet == 0)	continue		// exclude APCs which have powernet=0

			if(!unmarked || !P.powernet)		//if unmarked=1 we only return things with no powernet
				if(d == 0)
					. += P

		else if(istype(AM,/obj/structure/cable))
			var/obj/structure/cable/C = AM

			if(!unmarked || !C.powernet)
				if(C.d1 == d || C.d2 == d)
					. += C
	return .




//remove the old powernet and replace it with a new one throughout the network.
/proc/propagate_network(obj/O, datum/powernet/PN)
	//world.log << "propagating new network"
	var/list/worklist = list()
	var/list/found_machines = list()
	var/index = 1
	var/obj/P = null

	worklist+=O //start propagating from the passed object

	while(index<=worklist.len) //until we've exhausted all power objects
		P = worklist[index] //get the next power object found
		index++

		if( istype(P,/obj/structure/cable))
			var/obj/structure/cable/C = P
			if(C.powernet != PN) //add it to the powernet, if it isn't already there
				PN.add_cable(C)
			worklist |= C.get_connections() //get adjacents power objects, with or without a powernet

		else if(P.anchored && istype(P,/obj/machinery/power))
			var/obj/machinery/power/M = P
			found_machines |= M //we wait until the powernet is fully propagates to connect the machines

		else
			continue

	//now that the powernet is set, connect found machines to it
	for(var/obj/machinery/power/PM in found_machines)
		if(!PM.connect_to_network()) //couldn't find a node on its turf...
			PM.disconnect_from_network() //... so disconnect if already on a powernet


//Merge two powernets, the bigger (in cable length term) absorbing the other
/proc/merge_powernets(datum/powernet/net1, datum/powernet/net2)
	if(!net1 || !net2) //if one of the powernet doesn't exist, return
		return

	if(net1 == net2) //don't merge same powernets
		return

	//We assume net1 is larger. If net2 is in fact larger we are just going to make them switch places to reduce on code.
	if(net1.cables.len < net2.cables.len)	//net2 is larger than net1. Let's switch them around
		var/temp = net1
		net1 = net2
		net2 = temp

	//merge net2 into net1
	for(var/obj/structure/cable/Cable in net2.cables) //merge cables
		net1.add_cable(Cable)

	for(var/obj/machinery/power/Node in net2.nodes) //merge power machines
		if(!Node.connect_to_network())
			Node.disconnect_from_network() //if somehow we can't connect the machine to the new powernet, disconnect it from the old nonetheless

	return net1

//Determines how strong could be shock, deals damage to mob, uses power.
//M is a mob who touched wire/whatever
//power_source is a source of electricity, can be powercell, area, apc, cable, powernet or null
//source is an object caused electrocuting (airlock, grille, etc)
//No animations will be performed by this proc.
/proc/electrocute_mob(mob/living/carbon/M, power_source, obj/source, siemens_coeff = 1)
	if(istype(M.loc,/obj/mecha))	return 0	//feckin mechs are dumb
	if(istype(M,/mob/living/carbon/human))
		var/mob/living/carbon/human/H = M
		if(H.gloves)
			var/obj/item/clothing/gloves/G = H.gloves
			if(G.siemens_coefficient == 0)	return 0		//to avoid spamming with insulated glvoes on

	var/area/source_area
	if(istype(power_source,/area))
		source_area = power_source
		power_source = source_area.get_apc()
	if(istype(power_source,/obj/structure/cable))
		var/obj/structure/cable/Cable = power_source
		power_source = Cable.powernet

	var/datum/powernet/PN
	var/obj/item/weapon/stock_parts/cell/cell

	if(istype(power_source,/datum/powernet))
		PN = power_source
	else if(istype(power_source,/obj/item/weapon/stock_parts/cell))
		cell = power_source
	else if(istype(power_source,/obj/machinery/power/apc))
		var/obj/machinery/power/apc/apc = power_source
		cell = apc.cell
		if (apc.terminal)
			PN = apc.terminal.powernet
	else if (!power_source)
		return 0
	else
		log_admin("ERROR: /proc/electrocute_mob([M], [power_source], [source]): wrong power_source")
		return 0
	if (!cell && !PN)
		return 0
	var/PN_damage = 0
	var/cell_damage = 0
	if (PN)
		PN_damage = PN.get_electrocute_damage()
	if (cell)
		cell_damage = cell.get_electrocute_damage()
	var/shock_damage = 0
	if (PN_damage>=cell_damage)
		power_source = PN
		shock_damage = PN_damage
	else
		power_source = cell
		shock_damage = cell_damage
	var/drained_hp = M.electrocute_act(shock_damage, source, siemens_coeff) //zzzzzzap!
	var/drained_energy = drained_hp*20
	if (source_area)
		source_area.use_power(drained_energy/CELLRATE)
	else if (istype(power_source,/datum/powernet))
		var/drained_power = drained_energy/CELLRATE //convert from "joules" to "watts"
		PN.load+=drained_power
	else if (istype(power_source, /obj/item/weapon/stock_parts/cell))
		cell.use(drained_energy)
	return drained_energy

////////////////////////////////////////////////
// Misc.
///////////////////////////////////////////////


// return a knot cable (O-X) if one is present in the turf
// null if there's none
/turf/proc/get_cable_node()
	if(!can_have_cabling())
		return null
	for(var/obj/structure/cable/C in src)
		if(C.d1 == 0)
			return C
	return null

/area/proc/get_apc()
	for(var/obj/machinery/power/apc/APC in apcs_list)
		if(APC.area == src)
			return APC

///////////////////////////////////////////////
//Power machinery.
//////////////////////////////////////////////
/obj/machinery/power/modification //waveforms are stopped by all these machinery
	name = "you shouldn't be seeing this"
	desc = "A machine that can take incredibly high power loads and output them to nearby machines"
	icon = 'icons/wip/stock_parts.dmi'
	icon_state = "vbox_complete"
	density = 1
	anchored = 1
	var/voltage = 5000
	use_power = 0
	var/obj/machinery/power/controller/connected
	var/input_power = 500000
	var/output_power = 500000
	var/stored_power = 0
/obj/machinery/power/modification/New()
	..()
	connect_to_network()
	var/obj/machinery/power/controller/up = locate(/obj/machinery/power/controller) in get_step(src,NORTH)
	var/obj/machinery/power/controller/right = locate(/obj/machinery/power/controller) in get_step(src,EAST)
	var/obj/machinery/power/controller/down = locate(/obj/machinery/power/controller) in get_step(src,SOUTH)
	var/obj/machinery/power/controller/left = locate(/obj/machinery/power/controller) in get_step(src,WEST)
	if(up)
		up.update_connections()
	if(down)
		down.update_connections()
	if(left)
		left.update_connections()
	if(right)
		right.update_connections()
/obj/machinery/power/modification/examine(mob/user)
	user<<"The power storage gauge reads [stored_power]W with an input amount of [input_power]W"
/obj/machinery/power/modification/Destroy()
	..()
	if(connected)
		connected.connections.Remove(src)

/obj/machinery/power/modification/surge_protector
	name = "High Power Capacitor"
	desc = "A is able to store small amounts of power in order to create an UPS"
	var/max_amps = 500
	use_power = 0//handled directly inside the powernet datum for timing reasons.
	var/max_volts = 50000
/obj/machinery/power/modification/surge_protector/examine(mob/user)
	user<<"The surge rating reads [max_amps]A [max_volts]V"
/obj/machinery/power/modification/surge_protector/proc/protect()
	//not affected by temperature but they explode if they have too much power run through them
	var/total_dispersed = 0
	var/voltage_diff = 5//passive power usage is 25 watts
	var/current_diff = 5
	if(!powernet)
		return
	if(powernet.voltage > max_volts)//directly modify the current and voltage values so things don't explode on that tick  and then calculate the power loss
		voltage_diff = powernet.voltage - max_volts
		powernet.voltage -= voltage_diff
	if(powernet.get_current() > max_amps)
		current_diff = powernet.get_current() - max_amps
		powernet.current -= current_diff
	powernet.avail -= voltage_diff * current_diff
	//sort out the heating
	var/turf/simulated/location = loc
	if(loc)
		if(location.air)
			location.air.temperature += ((total_dispersed /1000000) * (total_dispersed/1000000))/2 //dispersing 1 mil watts is 0.5 heat per tick dispersing 4 mil watts it 8 heat per tick.
/obj/machinery/power/modification/surge_protector/attackby(obj/item/weapon/W , mob/user , params)
	if(istype(W , /obj/item/weapon/screwdriver))
		if(max_voltage + 10000 >= 200000)
			max_voltage = 50000
		else
			max_voltage += 10000
		user<<"<span class='notice'>You adjust the voltage setting on the [src.name] to [max_voltage]v</span>"
	else if(istype(W , /obj/item/device/multitool))
		if(max_amps + 100 >= 1000)
			max_amps = 100
		else
			max_amps += 100
		user<<"<span class='notice'>You adjust the amperage setting on the [src.name] to [max_amps]A</span>"

/obj/machinery/power/modification/power_collector
	name = "High power collector"
	desc = "A machine that can take incredibly high power loads and output them to nearby machines"
/obj/machinery/power/modification/power_collector/attackby(obj/item/W, mob/user, params)
	if(istype(W , /obj/item/weapon/screwdriver))
		if(input_power + 100000 > 5000000)
			input_power = 100000
		else
			input_power += 100000
		user<<"<span class='notice'>You adjust the [src.name]'s power input by 100000W to [input_power]W</span>"
	if(istype(W , /obj/item/weapon/wrench))
		if(anchored)
			user<<"<span class='notice'>You remove the [src.name]'s bolts.</span>"
			anchored = 0
			if(connected)
				connected.update_connections()
				connected = null
		else
			user<<"<span class='notice'>You secure the [src.name]'s bolts.</span>"
			anchored = 1
			var/obj/machinery/power/controller/up = locate(/obj/machinery/power/controller) in get_step(src,NORTH)
			var/obj/machinery/power/controller/right = locate(/obj/machinery/power/controller) in get_step(src,EAST)
			var/obj/machinery/power/controller/down = locate(/obj/machinery/power/controller) in get_step(src,SOUTH)
			var/obj/machinery/power/controller/left = locate(/obj/machinery/power/controller) in get_step(src,WEST)
			if(up)
				up.update_connections()
			if(down)
				down.update_connections()
			if(left)
				left.update_connections()
			if(right)
				right.update_connections()

/obj/machinery/power/modification/power_collector/examine(mob/user)
	user<<"The power storage gauge reads [stored_power]W with an input amount of [input_power]W"
/obj/machinery/power/modification/power_collector/proc/remove_power(amount)
	if(stored_power >= amount)
		stored_power -= amount
		return 1
	else
		return 0
/obj/machinery/power/modification/power_collector/process()

	if(powernet== null)
		return
	var/turf/simulated/location = loc
	if(loc)
		if(location.air)
			voltage -= (location.temperature /2)//rapidly drop the input voltage
			if(voltage <= 0)
				voltage = 1
			if(location.temperature >= 500)
				if(prob(5))
					var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
					smoke.set_up(loca = src.loc)
					smoke.start()
			if(location.temperature >= 5000)
				if(prob(5))
					var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
					s.set_up(5, 1, src)
					s.start()
					Destroy()
	if(stored_power + input_power <= 10000000)
		if(powernet.avail - powernet.load >= input_power)
			add_load(input_power)
			stored_power += input_power
		else
			stored_power += powernet.avail - powernet.load
			add_load(powernet.avail - powernet.load)
	voltage = powernet.voltage


		return

/obj/machinery/power/modification/power_capacitor
	name = "High Power Capacitor"
	desc = "A is able to store small amounts of power in order to create an UPS"
	var/max_power = 5000000
/obj/machinery/power/modification/power_capacitor/examine(mob/user)
	user<<"The power storage gauge reads [stored_power]W"
/obj/machinery/power/modification/power_capacitor/proc/remove_power(amount)
	if(stored_power >= amount)
		stored_power -= amount
		return 1
	else
		return 0
/obj/machinery/power/modification/power_capacitor/process()
	if(stored_power)
		var/turf/simulated/location = loc
		stored_power -= (stored_power/max_power) * 1000
		if(location)
			if(location.air)
				location.air.temperature += (stored_power/max_power) * 5
				if(location.temperature >= 500)
					if(prob(5))
						var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
						smoke.set_up(loca = src.loc)
						smoke.start()
						stored_power = 0
				if(location.temperature >= 5000)
					if(prob(5))
						var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
						s.set_up(5, 1, src)
						s.start()
						Destroy()
/obj/machinery/power/modification/power_capacitor/attackby(obj/item/weapon/W , mob/user , params)
	if(istype(W , /obj/item/weapon/wrench))
		if(anchored)
			user<<"<span class='notice'>You remove the [src.name]'s bolts.</span>"
			anchored = 0
			if(connected)
				connected.update_connections()
				connected = null
		else
			user<<"<span class='notice'>You secure the [src.name]'s bolts.</span>"
			anchored = 1
			var/obj/machinery/power/controller/up = locate(/obj/machinery/power/controller) in get_step(src,NORTH)
			var/obj/machinery/power/controller/right = locate(/obj/machinery/power/controller) in get_step(src,EAST)
			var/obj/machinery/power/controller/down = locate(/obj/machinery/power/controller) in get_step(src,SOUTH)
			var/obj/machinery/power/controller/left = locate(/obj/machinery/power/controller) in get_step(src,WEST)
			if(up)
				up.update_connections()
			if(down)
				down.update_connections()
			if(left)
				left.update_connections()
			if(right)
				right.update_connections()
/obj/machinery/power/modification/power_capacitor/proc/add_power(power)
	if(stored_power + power <= max_power)
		stored_power += power
		return 1
	else
		return 0
/obj/machinery/power/modification/power_emitter
	name = "High power disperser"
	desc = "A machine capable of rapidly transferring large amounts of power."
/obj/machinery/power/modification/power_emitter/proc/restore()
	var/excess = powernet.avail - powernet.load
	if(stored_power + excess <= 10000000)
		stored_power += excess
		add_load(excess)
	else
		add_load(10000000 - stored_power)
		stored_power += 10000000 - stored_power
/obj/machinery/power/modification/power_emitter/attackby(obj/item/W, mob/user, params)
	if(istype(W , /obj/item/weapon/screwdriver))
		if(output_power + 100000 > 5000000)
			output_power = 100000
		else
			output_power += 100000
		user<<"<span class='notice'>You adjust the [src.name]'s power output by 10000W to [output_power]W</span>"
	if(istype(W , /obj/item/weapon/wrench))
		if(anchored)
			user<<"<span class='notice'>You remove the [src.name]'s bolts.</span>"
			anchored = 0
			if(connected)
				connected.update_connections()
				connected = null
		else
			user<<"<span class='notice'>You secure the [src.name]'s bolts.</span>"
			anchored = 1
			var/obj/machinery/power/controller/up = locate(/obj/machinery/power/controller) in get_step(src,NORTH)
			var/obj/machinery/power/controller/right = locate(/obj/machinery/power/controller) in get_step(src,EAST)
			var/obj/machinery/power/controller/down = locate(/obj/machinery/power/controller) in get_step(src,SOUTH)
			var/obj/machinery/power/controller/left = locate(/obj/machinery/power/controller) in get_step(src,WEST)
			if(up)
				up.update_connections()
			if(down)
				down.update_connections()
			if(left)
				left.update_connections()
			if(right)
				right.update_connections()
/obj/machinery/power/modification/power_emitter/Destroy()
	..()
	if(connected)
		connected.connections.Remove(src)

/obj/machinery/power/modification/power_emitter/New()
	..()
	connect_to_network()

/obj/machinery/power/modification/power_emitter/examine(mob/user)
	user<<"The power storage gauge reads [stored_power]W with an output amount of [output_power]W"

/obj/machinery/power/modification/power_emitter/proc/add_power(amount)
	if((stored_power + amount) <= 10000000)
		stored_power += amount
		return 1
	else
		return 0

/obj/machinery/power/modification/power_emitter/process()
	if(!powernet)
		return
	if(stored_power >= output_power)
		add_avail(output_power,voltage)
		stored_power -= output_power
		return
/obj/machinery/power/controller
	name = "You should not see this"
	desc = "Groups input power into a single output without generating extra load."
	icon = 'icons/wip/stock_parts.dmi'
	icon_state = "vbox_connector"
	density = 1
	anchored = 1
	var/efficiency = 0.7//0.3 goes to heat in this case
	use_power = 0
	var/power = 0
	var/obj/machinery/power/connected
	var/list/connections = list()
/obj/machinery/power/controller/Destroy()
	SSmachine.processing -= src
/obj/machinery/power/controller/New()
	update_connections()
	var/obj/machinery/power/controller/up = locate(/obj/machinery/power/controller) in get_step(src,NORTH)
	var/obj/machinery/power/controller/right = locate(/obj/machinery/power/controller) in get_step(src,EAST)
	var/obj/machinery/power/controller/down = locate(/obj/machinery/power/controller) in get_step(src,SOUTH)
	var/obj/machinery/power/controller/left = locate(/obj/machinery/power/controller) in get_step(src,WEST)
	if(up)
		up.update_connections()
	if(down)
		down.update_connections()
	if(left)
		left.update_connections()
	if(right)
		right.update_connections()
	SSmachine.processing |= src
/obj/machinery/power/controller/attackby(obj/item/W, mob/user, params)
	if(istype(W , /obj/item/weapon/wrench))
		if(anchored)
			user<<"<span class='notice'>You remove the [src.name]'s bolts.</span>"
			anchored = 0
			update_connections()
		else
			user<<"<span class='notice'>You secure the [src.name]'s bolts.</span>"
			anchored = 1
			update_connections()
/obj/machinery/power/controller/proc/update_connections()
	for(var/obj/machinery/power/modification/m in connections)
		m.connected = null
	connections = list()
	if(!anchored)
		return
	var/obj/machinery/power/modification/up = locate(/obj/machinery/power) in get_step(src,NORTH)
	var/obj/machinery/power/modification/right = locate(/obj/machinery/power) in get_step(src,EAST)
	var/obj/machinery/power/modification/down = locate(/obj/machinery/power) in get_step(src,SOUTH)
	var/obj/machinery/power/modification/left = locate(/obj/machinery/power) in get_step(src,WEST)
	if(up)
		if(up.anchored)


			connections.Add(up)
	if(down)
		if(down.anchored)
			down.connected = src
			connections.Add(down)
	if(left)
		if(left.anchored)
			left.connected = src
			connections.Add(left)
	if(right)
		if(right.anchored)
			right.connected = src
			connections.Add(right)

/obj/machinery/power/controller/power_grouper
	name = "Power grouper"
	desc = "Groups input power into a single output without generating extra load."
	efficiency = 0.99
	var/voltage = 5000
/obj/machinery/power/controller/power_grouper/examine(mob/user)
	user<<"The power storage gauge reads [power]W"

/obj/machinery/power/controller/power_grouper/process()
	var/collectorn = 0
	var/emittern = 0
	var/evoltage = 0
	var/avail_power = 0
	var/starting_power = 0
	var/used_power = 0
	var/turf/simulated/location = loc
	if(loc)
		if(location.air)
			if(location.temperature >= 500)
				if(prob(5))
					var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
					smoke.set_up(loca = src.loc)
					smoke.start()
					efficiency -= efficiency / 50
					return
			else
				if(efficiency < 0.99)
					efficiency += 0.05
				if(efficiency >0.99)
					efficiency = 0.99
			if(location.temperature >= 5000)
				if(prob(5))
					var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
					s.set_up(5, 1, src)
					s.start()
					Destroy()
	for(var/obj/machinery/power/modification/power_emitter/emitter in connections)
		emittern ++
	for(var/obj/machinery/power/modification/power_collector/collector in connections)
		if(power + collector.stored_power <= 10000000)
			if(collector.remove_power(collector.stored_power))
				power += collector.stored_power
				starting_power += collector.stored_power
		else if(collector.stored_power >= 10000000 - power)
			collector.stored_power -= 10000000 - power
			power = 10000000
			starting_power += 10000000 - power
		collectorn ++
		evoltage += collector.voltage
	for(var/obj/machinery/power/modification/power_capacitor/capacitor in connections)
		avail_power += capacitor.stored_power
	if(collectorn)
		voltage = evoltage /collectorn//calculate the average voltage of the two inputs for the output.
	for(var/obj/machinery/power/modification/power_emitter/emitter in connections)//prioritise output connections first.
		if(power)
			if(emitter.add_power(power / emittern))
				power -= (power/emittern)
				emitter.voltage = voltage
				emittern --
			else
				emitter.add_power((10000000 - emitter.stored_power)/emittern)
				power -= (10000000 - emitter.stored_power)/emittern
				emittern --
				emitter.voltage = voltage
		else if((avail_power - used_power))
			if(emitter.add_power((avail_power - used_power)/emittern))
				used_power += (avail_power - used_power)/emittern
				emitter.voltage = voltage
				emittern --
			else
				emitter.add_power((10000000 - emitter.stored_power)/emittern)//evenly distribute the power between each of the machines
				used_power += (10000000 - emitter.stored_power)/emittern
				emittern --
				emitter.voltage = voltage
	for(var/obj/machinery/power/controller/power_transformer/transformer in connections)//then handle transformers
		if(power - transformer.output_power >= 0)
			if(transformer.add_power(transformer.output_power))
				power -= transformer.output_power
				transformer.starting_voltage = voltage
		else if((avail_power - used_power) - transformer.output_power >= 0)
			if(transformer.add_power(transformer.output_power))
				used_power += transformer.output_power
				transformer.starting_voltage = voltage
	if(used_power)
		used_power -= power//excess power is laying around so use that instead
		for(var/obj/machinery/power/modification/power_capacitor/capacitor in connections)

			if(used_power >= capacitor.stored_power)
				used_power -= capacitor.stored_power
				capacitor.stored_power -= capacitor.stored_power
			else
				capacitor.stored_power -= used_power
				used_power = 0
	if(power)
		//if we have left over power add it to the reamining capacitors
		for(var/obj/machinery/power/modification/power_capacitor/capacitor in connections)
			var/max_power = capacitor.max_power - capacitor.stored_power
			if(power >= max_power)
				capacitor.add_power(max_power)
				power -= max_power
			else
				capacitor.add_power(power)
				power = 0
	if(!istype(location,/turf/space))
		location.air.temperature += ((1-efficiency) * (voltage/60)) * (power /5000000)
		power -= (1-efficiency) * power
		if(power < 0)
			power = 0

/obj/machinery/power/controller/power_transformer
	name = "High voltage transformer"
	desc = "Groups input power into a single output without generating extra load."
	var/upperthreshold = 10
	var/lowerthreshold = 2
	efficiency = 0.7//0.3 goes to heat in this case
	var/voltage = 2
	var/starting_voltage = 5000
	var/output_power = 1200000
	var/inverted = 0
/obj/machinery/power/controller/power_transformer/attackby(obj/item/W, mob/user, params)
	if(istype(W , /obj/item/weapon/screwdriver))
		update_connections()//confirm that the devices haven't changed since before.
		if(voltage + 1 > upperthreshold)
			voltage = lowerthreshold
		else
			voltage += 1
		user<<"<span class='notice'>You adjust the [src.name]'s voltage amplifier setting to [voltage].</span>"
	if(istype(W , /obj/item/device/multitool))
		update_connections()//confirm that the devices haven't changed since before.
		inverted = !inverted
		user<<"<span class='notice'>You invert the [src.name]'s coil polarity setting to state [inverted].</span>"
	..()

/obj/machinery/power/controller/power_transformer/proc/add_power(amount)
	if(power + amount <= 3000000)
		power += amount
		return 1
	else
		return 0

/obj/machinery/power/controller/power_transformer/examine(mob/user)
	user<<"The power storage gauge reads [power]W with an output voltage of [voltage]"

/obj/machinery/power/controller/power_transformer/process()
	var/collectorn = 0
	var/voltagen = starting_voltage
	for(var/obj/machinery/power/modification/power_collector/collector in connections)
		if(power + collector.input_power <= 3000000)
			if(collector.remove_power(collector.input_power))
				power += collector.input_power
				voltagen += collector.voltage
	if(collectorn)
		voltagen = voltagen/collectorn
	for(var/obj/machinery/power/modification/power_emitter/emitter in connections)
		if(power - output_power >= 0)
			if(emitter.add_power(output_power*efficiency))
				power -= output_power
				if(inverted)
					emitter.voltage = voltage/voltage
				else
					emitter.voltage = voltagen * voltage
	var/turf/simulated/location = loc
	if(loc)
		if(location.air)
			if(location.temperature >= 500)
				if(prob(5))
					var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
					smoke.set_up(loca = src.loc)
					smoke.start()
					efficiency -= efficiency / 50
					return
			else
				if(efficiency < 0.7)
					efficiency += 0.05
				if(efficiency >0.7)
					efficiency = 0.7
			if(location.temperature >= 5000)
				if(prob(5))
					var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
					s.set_up(5, 1, src)
					s.start()
					Destroy()
			location.air.temperature += ((1-efficiency) * (voltage)) * (power/output_power) * 10

/obj/machinery/power/controller/Destroy()
	..()
	for(var/obj/machinery/power/modification/emitter in connections)
		emitter.connected = null