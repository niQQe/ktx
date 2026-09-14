


#define EZCSQC_WEAPONINFO	1
#define EZCSQC_PROJECTILE	2
#define EZCSQC_WEAPONDEF	4

#define PROJECTILE_ORIGIN		(1 << 0)
#define PROJECTILE_MODEL		(1 << 1)
#define PROJECTILE_ANGLES		(1 << 2)
#define PROJECTILE_OWNER		(1 << 3)
#define PROJECTILE_SPAWN_ORIGIN	(1 << 4)

#define WEAPONDEF_INIT		(1 << 0)
#define WEAPONDEF_FLAGS		(1 << 1)
#define WEAPONDEF_ANIM		(1 << 2)

#define WEPPREDANIM_SOUND		0x0001
#define WEPPREDANIM_PROJECTILE	0x0002
#define WEPPREDANIM_BRANCH		0x0040
#define WEPPREDANIM_MOREBYTES	0x0080
#define WEPPREDANIM_SOUND2		(0x0400 | WEPPREDANIM_MOREBYTES)
#define WEPPREDANIM_HAS(flags, flag) (((flags) & (flag)) == (flag))

string 	autocvar_r_rockettrail;
string 	autocvar_r_grenadetrail;
float	autocvar_r_rocketlight;
vector	autocvar_r_rocketlight_colour;
float	autocvar_cl_sproj_xerp;

int Projectile_FindTrail(int is_grenade)
{
	string cvar_to_use;
	int select;
	int trail_index = 0;
	
	if (is_grenade)
		cvar_to_use = autocvar_r_grenadetrail;
	else
		cvar_to_use = autocvar_r_rockettrail;
	select = stoi(cvar_to_use);
	
	switch (select)
	{
	case 0: // check for string, otherwise no trail
		if (cvar_to_use == "0")
		{
			trail_index = 0;
			break;
		}
		else
		{
			int effect = particleeffectnum(cvar_to_use);

			if (effect)
			{
				trail_index = effect;
				break;
			}
		}
		// fall through to default (so semicheat will work properly)
	case 1: // default model effect
	default:
		if (is_grenade)
			trail_index = particleeffectnum("TR_GRENADE");
		else
			trail_index = particleeffectnum("TR_ROCKET");
		break;
	case 2: // opposite effect
		if (is_grenade)
			trail_index = particleeffectnum("TR_ROCKET");
		else
			trail_index = particleeffectnum("TR_GRENADE");
		break;
	case 3: // alt rocket effect
		trail_index = particleeffectnum("TR_ALTROCKET");
		break;
	case 4: // gib
		trail_index = particleeffectnum("TR_BLOOD");
		break;
	case 5: // zombie gib
		trail_index = particleeffectnum("TR_SLIGHTBLOOD");
		break;
	case 6: // Scrag tracer
		trail_index = particleeffectnum("TR_WIZSPIKE");
		break;
	case 7: // Knight tracer
		trail_index = particleeffectnum("TR_KNIGHTSPIKE");
		break;
	case 8: // Vore tracer
		trail_index = particleeffectnum("TR_VORESPIKE");
		break;
	case 9: // rail trail
		trail_index = particleeffectnum("TE_RAILTRAIL");
		break;
	}
	
	return trail_index;
}


float Predraw_Projectile()
{
	float delta = time - self.s_time;
	if (autocvar_cl_sproj_xerp && self.ownnum != player_localentnum && self.ownnum != 0)
		delta += ping_time;
	
	self.origin = self.s_origin;
	self.origin += self.velocity * delta;
	setorigin(self, self.origin);
	
	// we need to space out the particles incase we're running at very high fps
	if (time > self.p_time)
	{
		if (self.p_time) // we want to draw at least 1 frame worth of trail, lest cl_sproj_xerp stop any trails from existing
		{
			traceline(self.oldorigin, self.origin, MOVE_NOMONSTERS, self);
			if (trace_fraction < 1)
			{
				self.oldorigin = trace_endpos;
				return PREDRAW_NEXT;
			}
		}
		
		if (self.traileffectnum)
			trailparticles(self.traileffectnum, self, self.oldorigin, self.origin);
		
		self.p_time = time + 0.013;
		self.oldorigin = self.origin;
	}
	
	if (self.modelflags & MF_ROCKET)
	{
		dynamiclight_add(self.origin, 200, autocvar_r_rocketlight_colour, 0);
	}
	
	return PREDRAW_AUTOADD;
}


void EntUpdate_Projectile(float is_new)
{
	int sendflags = ReadByte();
	
	if (sendflags & PROJECTILE_ORIGIN)
	{
		self.s_origin = [ReadCoord(), ReadCoord(), ReadCoord()];
		self.velocity = [ReadCoord(), ReadCoord(), ReadCoord()];
		self.s_time = ReadFloat();
	}
	
	
	if (sendflags & PROJECTILE_MODEL)
	{
		// Reki: note- we need to do this monstrosity of a setmodel because setmodelindex doesn't return modelflags
		setmodel(self, modelnameforindex(ReadShort()));	
		self.effects = ReadShort();
	}
	
	
	if (sendflags & PROJECTILE_ANGLES)
	{
		self.angles = [ReadAngle(), ReadAngle(), ReadAngle()];
	}
	
	
	if (sendflags & PROJECTILE_OWNER)
	{
		self.ownnum = ReadEntityNum();
	}

	if (sendflags & PROJECTILE_SPAWN_ORIGIN)
	{
		vector spawn_origin = [ReadCoord(), ReadCoord(), ReadCoord()];
		if (vlen(spawn_origin - self.s_origin) < 150)
			self.oldorigin = spawn_origin;
	}
	
	
	if (is_new)
	{
		self.drawmask = MASK_ENGINE;
		self.predraw = Predraw_Projectile;
		
		self.effects |= EF_NOSHADOW;
		if (self.modelflags & MF_ROCKET)
			self.traileffectnum = Projectile_FindTrail(FALSE);
		else if (self.modelflags & MF_GRENADE)
			self.traileffectnum = Projectile_FindTrail(TRUE);
		
		if (self.oldorigin == '0 0 0')
			self.oldorigin = self.s_origin;
		
		if !(PredProjectile_MatchProjectile())
			is_new = 2;
	}
}

void EntUpdate_WeaponDef(float is_new)
{
	int sendflags = ReadByte();
	ReadByte();

	if (sendflags & WEAPONDEF_INIT)
	{
		ReadShort();
		ReadShort();
	}

	if (sendflags & WEAPONDEF_FLAGS)
	{
		ReadByte();
		ReadByte();
	}

	if (sendflags & WEAPONDEF_ANIM)
	{
		int anim_number = ReadByte();
		int k;
		for (int i = 0; i < anim_number; ++i)
		{
			int anim_flags;
			ReadByte();
			anim_flags = ReadByte();
			if (anim_flags & WEPPREDANIM_MOREBYTES)
				anim_flags |= ReadByte() << 8;
			if (anim_flags & WEPPREDANIM_SOUND)
			{
				ReadShort();
				ReadShort();
			}
			if (WEPPREDANIM_HAS(anim_flags, WEPPREDANIM_SOUND2))
			{
				ReadShort();
				ReadShort();
			}
			if (anim_flags & WEPPREDANIM_PROJECTILE)
			{
				ReadShort();
				for (k = 0; k < 3; ++k)
					ReadShort();
				for (k = 0; k < 3; ++k)
					ReadByte();
			}
			ReadByte();
			if (anim_flags & WEPPREDANIM_BRANCH)
				ReadByte();
			ReadByte();
		}
	}
}






void(float apilevel, string enginename, float engineversion) CSQC_Init
{
	WeaponPred_Init();
	
	precache_model("progs/missile.mdl");
	precache_model("progs/spike.mdl");
	precache_model("progs/s_spike.mdl");
	
	registercvar("cl_predict_weaponsound", "1");
	registercvar("cl_sproj_xerp", "0");
}


float(float entnum, float channel, string soundname, float vol, float attenuation, vector pos, float pitchmod, float flags) CSQC_Event_Sound
{
	if (entnum == player_localentnum)
	{
		if (channel == CHAN_WEAPON)
		{
			if (autocvar_cl_predict_weaponsound == 1)
				return TRUE;
			else if (autocvar_cl_predict_weaponsound > 1)
				return PM_FilterWeaponSound(soundname);
		}
	}
	
	
	return FALSE;
}


void(float is_new) CSQC_Ent_Update
{
	int ent_type = ReadByte();
	
	switch (ent_type)
	{
		case EZCSQC_PROJECTILE: EntUpdate_Projectile(is_new); break;
		case EZCSQC_WEAPONINFO: EntUpdate_WeaponPred(is_new); break;
		case EZCSQC_WEAPONDEF: EntUpdate_WeaponDef(is_new); break;
		
		
	}
}


void(float vwidth, float vheight, float notmenu) CSQC_UpdateView
{
	ping_time = getplayerkeyfloat(player_localnum, INFOKEY_P_PING) / 1000;
	chat_info = stof(getlocaluserinfo(0, "chat"));
	
	clearscene();
	setproperty(VF_DRAWENGINESBAR, TRUE);
	setproperty(VF_DRAWCROSSHAIR, TRUE);
	addentities(MASK_ENGINE | (intermission?0:MASK_PRED_VIEWMODEL));
	renderscene();
}
