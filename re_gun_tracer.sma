#include <amxmodx>
#include <reapi>
#include <hamsandwich>
#include <fakemeta>
#include <xs>

//#define DEBUG

// interval for querying "cl_righthand" for all clients (in seconds)
#define QUERYCVAR_INTERVAL 5.0

new Trie:g_tEntityClasses;

// gunfire data
new g_iEntity, g_iAttacker;
new Float:g_vEndPos[3];

// player vars
new bool:g_bRightHand[MAX_PLAYERS + 1];

// binding cvars
new g_cvarFirstPerson, g_cvarThirdPerson, g_cvarAlive, 
	g_cvarSharpColor, g_cvarLength, Float:g_cvarSpeed, 
	g_cvarRandomize;

public plugin_precache()
{
	g_tEntityClasses = TrieCreate();
	register_forward(FM_Spawn, "OnEntSpawn_Post", 1);
}

public plugin_init()
{
	register_plugin("[RE] Gun Tracer", "0.1", "holla");

	// hooks
	RegisterHookChain(RG_CBaseEntity_FireBullets3,  "OnFireBullet3");
	RegisterHookChain(RG_CBaseEntity_FireBullets3,  "OnFireBullet3_Post", 1);
	RegisterHookChain(RG_CBaseEntity_FireBuckshots, "OnFireBuckshots");
	RegisterHookChain(RG_CBaseEntity_FireBuckshots, "OnFireBuckshots_Post", 1);

	RegisterHam(Ham_TraceAttack, "worldspawn", "OnTraceAttack_Post", 1);
	RegisterHam(Ham_TraceAttack, "player",     "OnTraceAttack_Post", 1);
	TrieSetCell(g_tEntityClasses, "worldspawn", 1);
	TrieSetCell(g_tEntityClasses, "player", 1);

	// cvars:

	// show gun tracer in first person (also affect on who spectating you)
	bind_pcvar_num(create_cvar("guntracer_first_person", "1"), g_cvarFirstPerson);

	// show gun tracer in third person
	bind_pcvar_num(create_cvar("guntracer_third_person", "1"), g_cvarThirdPerson);

	// show gun tracer for alive players
	// (0 is useful for some servers that prefer a more formal match)
	// (2 = show only your own tracer when you're alive)
	bind_pcvar_num(create_cvar("guntracer_alive", "1"),        g_cvarAlive);

	// use a sharper tracer color (first person)
	// actually TE_USERTRACER can change 12 different colors,
	// but i dont want this becomes rainbow, so, only two color here :/
	bind_pcvar_num(create_cvar("guntracer_sharp_color", "1"),  g_cvarSharpColor);

	// tracer length (1~255) (first person)
	bind_pcvar_num(create_cvar("guntracer_length", "4"),       g_cvarLength);

	// randomize the color(a light and a sharper yellow) and length(1~7) (first person)
	bind_pcvar_num(create_cvar("guntracer_randomize", "1"),    g_cvarRandomize);
	
	// tracer speed (first pernson)
	bind_pcvar_float(create_cvar("guntracer_speed", "3072"),   g_cvarSpeed);

	// v_model attachment is client side,
	// so we need to create a dummy entity to get the attachment
	// and roughly calculate the final gunpoint for right hand
	g_iEntity = rg_create_entity("info_target");

	// if debug is enabled, you can see a dummy entity every time the gun fires
#if !defined DEBUG
	set_entvar(g_iEntity, var_effects, get_entvar(g_iEntity, var_effects) | EF_NODRAW);
#endif

	// initialize the fire state for OnTraceAttack_Post()
	state nofire;

	// a repeated task for querying the "cl_righthand" for all clients in every x seconds
	set_task(QUERYCVAR_INTERVAL, "TaskCheckRightHand", .flags="b"); 
}

// called when a entity spawn
public OnEntSpawn_Post(entity)
{
	// null entity?
	if (!pev_valid(entity))
		return;

	static classname[32];
	get_entvar(entity, var_classname, classname, charsmax(classname));

	// not registered?
	if (!TrieKeyExists(g_tEntityClasses, classname))
	{
		// register hook for this entity class
		RegisterHam(Ham_TraceAttack, classname, "OnTraceAttack_Post");
		TrieSetCell(g_tEntityClasses, classname, 1);
	}
}

// called when a gun fires (not shotgun)
public OnFireBullet3(entity)
{
	// player only
	if (is_user_alive(entity))
	{
		state firebullet3; // dunno what will happen if other plugin returns a SUPERCEDE here :S
		g_iAttacker = entity; // needed?
	}
	else
	{
		state nofire;
	}
}
public OnFireBullet3_Post(entity)
{
	state nofire;
	g_iAttacker = 0;

	FireTracer(entity, g_vEndPos);
}

// called when a shotgun fires
public OnFireBuckshots(entity)
{
	// player only
	if (is_user_alive(entity))
	{
		state firebuckshots; // dunno what will happen if other plugin returns a SUPERCEDE here :S
		g_iAttacker = entity; // needed?
	}
	else
	{
		state nofire;
	}
}
public OnFireBuckshots_Post(entity)
{
	state nofire;
	g_iAttacker = 0;
}

// TraceAttack hook
public OnTraceAttack_Post(id, attacker, Float:damage, Float:vdir[3], tr) <nofire> {}
public OnTraceAttack_Post(id, attacker, Float:damage, Float:vdir[3], tr) <firebullet3>
{
	if (g_iAttacker != attacker) // needed?
		return;

	// record the last endpos
	get_tr2(tr, TR_vecEndPos, g_vEndPos);
}
public OnTraceAttack_Post(id, attacker, Float:damage, Float:vdir[3], tr) <firebuckshots>
{
	if (g_iAttacker != attacker || !is_user_alive(attacker)) // needed?
		return;

	// special handling for shotguns
	static Float:vsrc[3], Float:vendpos[3];
	ExecuteHam(Ham_Player_GetGunPosition, attacker, vsrc);
	get_tr2(tr, TR_vecEndPos, vendpos);

	FireTracer(attacker, vendpos);
}

// called when a player joined the server
public client_putinserver(id)
{
	if (!is_user_bot(id))
		query_client_cvar(id, "cl_righthand", "QueryCvarRightHand");
}

// task for checking player is right-handed
public TaskCheckRightHand()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (is_user_connected(i) && !is_user_bot(i))
			query_client_cvar(i, "cl_righthand", "QueryCvarRightHand");
	}
}

// query "cl_righthand" result for the client
public QueryCvarRightHand(id, const cvar[], const value[])
{
	g_bRightHand[id] = str_to_num(value) ? true : false;
}

// fire a tracer
FireTracer(id, Float:vendpos[3])
{
	static Float:vsrc[3], Float:vangle[3];
	ExecuteHam(Ham_Player_GetGunPosition, id, vsrc);
	get_entvar(id, var_v_angle, vangle);
	vangle[0] *= -1.0;

	// or use MakeVectors and global_get(v_forward, v_right, v_up) is better? whatever :/
	static Float:vfwd[3], Float:vright[3], Float:vup[3];
	angle_vector(vangle, ANGLEVECTOR_FORWARD, vfwd);
	angle_vector(vangle, ANGLEVECTOR_RIGHT, vright);
	angle_vector(vangle, ANGLEVECTOR_UP, vup);

	// calulate the position offset that affected by angle.x
	new Float:ax = vangle[0];
	new Float:addfwd = ax / 89.0;
	new Float:addup = floatabs(ax) / 89.0 - 1.0;

	static Float:origin[3];
	origin[0] = vsrc[0] + vfwd[0] * addfwd + vup[0] * addup;
	origin[1] = vsrc[1] + vfwd[1] * addfwd + vup[1] * addup;
	origin[2] = vsrc[2] + vfwd[2] * addfwd + vup[2] * addup;

	// fix the angle that affected by punchangle (recoil)
	static Float:punchangle[3];
	get_entvar(id, var_punchangle, punchangle);
	vangle[0] += punchangle[0];

	// set props for the dummy entity
	static viewmodel[64];
	get_entvar(id, var_viewmodel, viewmodel, charsmax(viewmodel));
	engfunc(EngFunc_SetModel, g_iEntity, viewmodel);
	engfunc(EngFunc_SetOrigin, g_iEntity, origin);

	// some useless thing :>
	enum HAND
	{
		LH, // left hand
		RH  // right hand
	};

	static Float:gunpos[HAND][3], Float:velocity[HAND][3];
	if (get_user_weapon(id) == CSW_ELITE)
	{
		// lazy to compensate the punchangle.y :<
		set_entvar(g_iEntity, var_angles, vangle);

		// special handleing for the dual elite
		new activeitem = get_member(id, m_pActiveItem);
		new index = (WeaponState:get_member(activeitem, m_Weapon_iWeaponState) & WPNSTATE_ELITE_LEFT) ? 1 : 0;
		GetAttachment(g_iEntity, index, gunpos[LH]);
		GetAttachment(g_iEntity, !index, gunpos[RH]);
	}
	else if (get_member(id, m_bOwnsShield))
	{
		// shield is always right-handed
		vangle[1] -= punchangle[1]; // compensate by the punchangle.y
		set_entvar(g_iEntity, var_angles, vangle);
		GetAttachment(g_iEntity, 1, gunpos[LH]);
		gunpos[RH] = gunpos[LH];
	}
	else
	{
		// fix the angle by compensating the punchangle (not sure if this is a correct approach?
		static Float:newangle[3]; newangle = vangle;
		newangle[1] = vangle[1] - punchangle[1];
		set_entvar(g_iEntity, var_angles, newangle);
		GetAttachment(g_iEntity, 0, gunpos[LH]);

		// compensate for the right hand
		newangle[1] = vangle[1] + punchangle[1];
		set_entvar(g_iEntity, var_angles, newangle);
		GetAttachment(g_iEntity, 0, gunpos[RH]); // this is not the final result

		// we still have to calculate the final right hand position here
		static Float:offset[3];
		xs_vec_sub(gunpos[RH], origin, offset);
		xs_vec_mul_scalar(vright, 2.0 * xs_vec_dot(offset, vright), vright);
		xs_vec_sub(offset, vright, offset);
		xs_vec_add(origin, offset, gunpos[RH]);
	}

	// calculate tracer velocity for both hands (am i abusing the loop? :S)
	for (new HAND:i = LH; i < HAND; i++)
	{
		xs_vec_sub(vendpos, gunpos[i], velocity[i]);
		xs_vec_normalize(velocity[i], velocity[i]);
		xs_vec_mul_scalar(velocity[i], g_cvarSpeed, velocity[i]);
	}

	static HAND:h, bool:alive;
	new color = g_cvarRandomize ? random_num(4, 5) : g_cvarSharpColor ? 5 : 4;
	new length = g_cvarRandomize ? random_num(1, 7) : g_cvarLength;

	// loop through all players
	for (new i = 1; i <= MaxClients; i++)
	{
		// filter bots and not connected
		if (!is_user_connected(i) || is_user_bot(i))
			continue;

		// filter alive players if specified
		alive = bool:is_user_alive(i);
		if ((!g_cvarAlive && alive) || (g_cvarAlive == 2 && alive && i != id))
			continue;

		// is self or who spectating me
		if (i == id || (!alive && get_entvar(i, var_iuser2) == id && get_entvar(i, var_iuser1) == OBS_IN_EYE))
		{
			if (g_cvarFirstPerson)
			{
				// draw a TE_USERTRACER in first person
				h = g_bRightHand[i] ? RH : LH;
				FX_UserTracer(i, gunpos[h], velocity[h], 5, color, length);
			}
		}
		else if (g_cvarThirdPerson)
		{
			// draw a TE_TRACER in 3rd person (this is because TE_USERTRACER can shoot through any wall)
			FX_Tracer(i, vsrc, vendpos);
		}
	}
}

// some useful stocks:

stock FX_UserTracer(player, Float:origin[3], Float:velocity[3], life, color, length)
{
	message_begin(player ? MSG_ONE_UNRELIABLE : MSG_BROADCAST, SVC_TEMPENTITY, .player=player);
	write_byte(TE_USERTRACER);
	write_coord_f(origin[0]);
	write_coord_f(origin[1]);
	write_coord_f(origin[2]);
	write_coord_f(velocity[0]);
	write_coord_f(velocity[1]);
	write_coord_f(velocity[2]);
	write_byte(life);
	write_byte(color);
	write_byte(length);
	message_end();
}

stock FX_Tracer(player, Float:start[3], Float:end[3])
{
	message_begin(player ? MSG_ONE_UNRELIABLE : MSG_BROADCAST, SVC_TEMPENTITY, .player=player);
	write_byte(TE_TRACER);
	write_coord_f(start[0]);
	write_coord_f(start[1]);
	write_coord_f(start[2]);
	write_coord_f(end[0]);
	write_coord_f(end[1]);
	write_coord_f(end[2]);
	message_end();
}