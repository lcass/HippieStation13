/obj/structure/stool/bed/chair/e_chair
	name = "electric chair"
	desc = "Looks absolutely SHOCKING!\n<span class='notice'>Alt-click to rotate it clockwise.</span>"
	icon_state = "echair0"
	var/obj/item/assembly/shock_kit/part = null
	var/last_time = 1

/obj/structure/stool/bed/chair/e_chair/New()
	..()
	overlays += image('icons/obj/objects.dmi', src, "echair_over", MOB_LAYER + 1, dir)
	return

/obj/structure/stool/bed/chair/e_chair/attackby(obj/item/weapon/W, mob/user, params)
	if(istype(W, /obj/item/weapon/wrench))
		var/obj/structure/stool/bed/chair/C = new /obj/structure/stool/bed/chair(loc)
		playsound(loc, 'sound/items/Ratchet.ogg', 50, 1)
		C.dir = dir
		part.loc = src.loc
		part.master = null
		part = null
		qdel(src)
		return
	return

/obj/structure/stool/bed/chair/e_chair/rotate()
	..()
	overlays.Cut()
	overlays += image('icons/obj/objects.dmi', src, "echair_over", MOB_LAYER + 1, dir)	//there's probably a better way of handling this, but eh. -Pete
	return

/obj/structure/stool/bed/chair/e_chair/proc/shock()
	if(last_time + 50 > world.time)
		return
	last_time = world.time

	// special power handling
	var/obj/structure/cable/cable = locate(/obj/structure/cable) in src.loc
	if(!cable)
		return
	if(!cable.powernet)
		return
	if(cable.powernet.avail - cable.powernet.load >= 100000)
		if(cable.powernet.voltage >= 50000)
			cable.add_load(100000)
			flick("echair1", src)
			var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
			s.set_up(12, 1, src)
			s.start()
			if(buckled_mob)
				buckled_mob.burn_skin(85)
				buckled_mob << "<span class='userdanger'>You feel a deep shock course through your body!</span>"
				sleep(1)
				buckled_mob.burn_skin(85)
			visible_message("<span class='danger'>The electric chair went off!</span>", "<span class='italics'>You hear a deep sharp shock!</span>")
		else
			var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
			s.set_up(2, 1, src)
			s.start()
			visible_message("<span class='danger'>The electric chair fizzles slightly</span>")
			electrocute_mob(buckled_mob, cable.powernet, src.loc, 0.1)
	return