## Description:
This AMXX plugin adds a tracer effect to guns, displaying the trajectory of the shots. \
Where tracers(TE_USERTRACER) are fired from the actual gunpoint of v_model in first person (also support for who spectating you) \
In the third person, tracers(TE_TRACER) just fire from the player origin+viewofs \
Support for shotguns, dual elite, shield also. \
**NOTE: This plugin only tested with original weapons, may not work properly for custom weapons.**

## Requirements:
- amxmodx 1.9 or newer
- rehlds
- regamedll
- reapi

## Video
[![youtube](https://img.youtube.com/vi/6W1q6nwriDw/0.jpg)](https://www.youtube.com/watch?v=6W1q6nwriDw)

## CVARs
```pawn
// show gun tracer in first person (also affect on who spectating you)
guntracer_first_person 1

// show gun tracer in third person
guntracer_third_person 1

// show gun tracers to alive players
// (0 is useful for some servers that prefer a more formal match)
// (2 = show only your own tracer when you're alive)
guntracer_alive 1

// use a sharper tracer color (first person)
// actually TE_USERTRACER can change 12 different colors,
// but i dont want this becomes rainbow, so only two colors here :/
guntracer_sharp_color 1

// tracer length (1~255) (first person)
guntracer_length 4

// randomize the color(a light and a sharper yellow) and length(1~7) (first person)
guntracer_randomize 1

// tracer speed (first person)
guntracer_speed 3072
```