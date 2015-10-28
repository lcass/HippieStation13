////////////////////////////////////////////
// POWERNET DATUM
// each contiguous network of cables & nodes
/////////////////////////////////////
/datum/powernet
	var/list/cables = list()	// all cables & junctions
	var/list/nodes = list()		// all connected machines

	var/load = 0				// the current load on the powernet, increased by each machine at processing
	var/newavail = 0			// what available power was gathered last tick, then becomes...
	var/avail = 0				//...the current available power in the powernet
	var/viewload = 0			// the load as it appears on the power console (gradually updated)
	var/number = 0				// Unused //TODEL
	var/netexcess = 0			// excess power on the powernet (typically avail-load)///////
	var/voltage = 5000 //set it to the default , different power sources can provide different voltages and different machines can use different voltages
	var/current = 0
	var/current_threshold = 3
	var/voltage_threshold = 500
	var/use_power = 0
	var/colliding = 0
	var/new_waveform = 0
	var/waveform = 0 //for an upcoming powernet update
/datum/powernet/New()

	SSmachine.powernets += src

/datum/powernet/proc/add_avail(var/power , var/pvoltage)
	var/ccurrent = 0//as it's not calculated at each point find the average voltage over the entire system and just use that.
	if(avail && voltage)
		ccurrent = (newavail/voltage)
	var/acurrent = (power/pvoltage)
	newavail+=power
	if(ccurrent || acurrent)
		voltage = newavail/(ccurrent+acurrent)
	current = get_current()
/datum/powernet/proc/add_waveform(var/waveform)
	if(new_waveform)//more than one waveform generator causes you to have interference and he dampening of the second signal
		new_waveform += waveform/new_waveform
		colliding = 1
	else
		new_waveform = waveform
		colliding = 0
/datum/powernet/proc/get_current()
	if(!avail)
		return 0
	if(!voltage)
		return 0
	return (avail/voltage)

/datum/powernet/Destroy()
	//Go away references, you suck!
	for(var/obj/structure/cable/C in cables)
		cables -= C
		C.powernet = null
	for(var/obj/machinery/power/M in nodes)
		nodes -= M
		M.powernet = null
	SSmachine.powernets -= src
	return ..()

/datum/powernet/proc/is_empty()
	return !cables.len && !nodes.len

//remove a cable from the current powernet
//if the powernet is then empty, delete it
//Warning : this proc DON'T check if the cable exists
/datum/powernet/proc/remove_cable(obj/structure/cable/C)
	cables -= C
	C.powernet = null
	if(is_empty())//the powernet is now empty...
		qdel(src)///... delete it

//add a cable to the current powernet
//Warning : this proc DON'T check if the cable exists
/datum/powernet/proc/add_cable(obj/structure/cable/C)
	if(C.powernet)// if C already has a powernet...
		if(C.powernet == src)
			return
		else
			C.powernet.remove_cable(C) //..remove it
	C.powernet = src
	cables +=C

//remove a power machine from the current powernet
//if the powernet is then empty, delete it
//Warning : this proc DON'T check if the machine exists
/datum/powernet/proc/remove_machine(obj/machinery/power/M)
	nodes -=M
	M.powernet = null
	if(is_empty())//the powernet is now empty...
		qdel(src)///... delete it


//add a power machine to the current powernet
//Warning : this proc DON'T check if the machine exists
/datum/powernet/proc/add_machine(obj/machinery/power/M)
	if(M.powernet)// if M already has a powernet...
		if(M.powernet == src)
			return
		else
			M.disconnect_from_network()//..remove it
	M.powernet = src
	nodes[M] = M

/datum/powernet/proc/reset()
	//see if there's a surplus of power remaining in the powernet and stores unused power in the SMES
	netexcess = avail - load
	if(netexcess > 100 && nodes && nodes.len)		// if there was excess power last cycle
		for(var/obj/machinery/power/smes/S in nodes)	// find the SMESes in the network
			S.restore()	// and restore some of the power that was used
		for(var/obj/machinery/power/modification/power_emitter/E in nodes)
			E.restore()
	//updates the viewed load (as seen on power computers)
	viewload = 0.8*viewload + 0.2*load
	viewload = round(viewload)
	//reset the powernet
	load = 0
	avail = newavail
	newavail = 0
	waveform = new_waveform
	current = get_current()
	for(var/obj/machinery/power/modification/surge_protector/surge in nodes)
		surge.protect()
	if(current >= current_threshold || voltage >= voltage_threshold)
		var/limit = rand(0,cables.len/10)
		for(var/i = 0 , i < limit, i++)
			var/obj/structure/cable/chosen_cable = pick(cables)
			chosen_cable.overload_enact(current,voltage)
			chosen_cable.waveform_enact(waveform,colliding)
/datum/powernet/proc/get_electrocute_damage()
	if((avail/voltage) >= 0.5)
		return Clamp(round((avail/voltage)/10), 10, 90) + rand(-5,5)
	else
		return 0