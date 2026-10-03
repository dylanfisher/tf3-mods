---
title: Common Pitfalls and Best Practices
page_id: modding:general:bestpractice
source: https://wiki.transportfever3.com/doku.php?id=modding:general:bestpractice
---

# Common Pitfalls and Best Practices

An overview of good workflows to prevent bad performance, cleanup work and errors later on. Its intended to increase understanding of some technical topics related to content creation.

## Common pitfalls

Some concepts of game engines can be difficult to grasp if you're not working directly in the games industry. To give some insight on what's happening behind the scenes and why its important, this section will list some of the bottlenecks of modern rendering, as well as specifics to Transport Fever 3.

### Draw Calls and Lods

![](../../_media/modding/general/drawcalls.png)**Draw Calls are a major source of performance impact in TF3.** When working on a model, you can see your materials and meshes as unique instructions getting sent by the CPU to the GPU. **Unique combinations of materials and meshes** adds to the total number of instructions that are needed to render the full model. The amount of draw calls displayed for a model is roughly(!) the sum of these instructions. **The more individual meshes and materials, the higher the draw call number**. Some rules of thumb:

- New meshes start new draw calls, new materials as well
- Using **Mesh Instances that have the same material doesn't create new draw calls** for the instances
- Skinned meshes always generate new draw calls, even on instances ( = same mesh/material) .
- Sorted Materials also always generate new draw calls per instance
- Vehicle materials should be split into an exterior and interior material. This makes the later lods as optimized as possible, since interior can just be deleted and the exterior can still use the full texture. Same for small detail meshes with additional textures that can be disabled in later lods.
- A higher amount of draw calls for lod0 is generally reasonable, but should serve a purpose. For example glass windows can be split into separate local groups to improve sorting. Generally splitting every object is not recommended, since it increases draw calls quite fast.

---

![](../../_media/modding/general/draw_calls_lod0.png) In terms of re-usability and Texel Size, sometimes there are not really good alternatives to using separate materials; at least for lod0. This in general is fine and common standard in Transport Fever 3 as well as other current-gen games. The focus is more on **reducing the number of draw calls for later lods** by merging objects, **removing small detail materials like glasses** and also **combining textures onto a single texture set** (explained down below), saving the need for separate materials in the process.

- For most gameplay scenarios, total number of Draw Calls is probably bottlenecking earlier than the total polycount.
- Thus its required to reduce not only the polycount per lod but also the amount of Draw Calls.
- This can be achieved by removing small detail materials and merging meshes, especially individual glasses from lod1 onwards
- For lod0 in general its fine to have a higher number of draw calls as long as it can reasonably be explained and it switches to an optimized lod1 at distance 50-100.
- Its smart to plan your materials a bit beforehand in terms of Draw Calls, to have an easier time optimizing them later down the road.

---

![](../../_media/modding/general/draw_calls_last_lod.png) As mentioned (generally speaking) a higher number of Draw Calls in lod0 is not the biggest issue, it becomes more of a problem if later lods still retain a high number of Draw Calls and cannot fallback to a low single digit number. The more we zoom out, the more they add up. Especially for the last lod, just a single draw call is the optimal target.

For vehicles its often easy to just keep the chassis/shell of the vehicle as the last remaining mesh and material, but it can be a bit of a challenge for buildings. They often use separate trim sheets or tileable textures for ceiling, walls and ground and still have a noticable color contrast from a far distance that cannot be discarded easily without some really visible plopping between lod levels.

That's where the process of [Material Baking](../../modding/tools/external/blender.md#material_baking) can come in handy.

### Polycount and Lods

![](../../_media/modding/general/polycount_lods.png)Polycount is measured as the total number of triangles that make up a mesh. A reasonable polycount in lod0 is strongly recommended to keep the game running smoothly even with dozens of the same vehicle spawned. Even more important than the lod0 polycount is proper fallback in later lods. When the camera zooms out, **the camera will need to render more objects, thus each individual object needs to have fewer triangles; proportionally to its size on the screen**.

- lod0 polycount should be in the range defined in the guidelines
- each lod should be a meaningful reduction to its predecessor. Internally, we aim for 1/4th reduction
- **The last lod needs to be as simple as possible** and can be aggressively reduced. Getting down to 1000 triangles is realistic for most models
- Automatic polygon reduction can help, but some options provide better results than others. For most models, un-subdividing models should be preferred over random polyreduce.
- Generally, **two lods in addition to the base lod should be sufficient** for most models. **More lods dont necessarily improve performance.**
- For a model, every lod always resides in the RAM. More lods mean more RAM usage. Its good practice to prevent redundant lods.
- If you feel like you cannot reduce the draw calls anymore for the last lod due to plopping, you could try increasing the distance if this enables you to go lower. This is generally the better tradeoff since the draw call count on the last lod quickly adds up.
- Also, getting rid of the transparent materials from lod1 onwards has performance advantages since they are more expensive to render compared to opaque

### Icons

Icons can be generated using the model editor. Its important to have all relevant icons shipped with the mod to support all of the menu items, including cblend masks.

We strongly encourage using cblend for some models in your mod since most players like tinting their vehicles.

## Best practices

### Content Creation

#### Materials, Textures & UVs

##### Trim sheets for multiple different materials on a single texture

![](../../_media/modding/general/trim_sheets.png)Trim sheets are basically strips of different materials packed onto a single texture. In most cases they are tileable horizontally and stacked vertically.

This way you can get a lot out of a single material/texture by overlapping the uvs in the areas where you need them. And the final model will only have a single draw call.

**Different materials still make sense if you need different shaders like Physical or Transparent.**

##### Tileable textures for layouting of complex patterns (and optimizing texel density)

![](../../_media/modding/general/tileable_textures.png)Similarly, single tileable textures can be salvaged in the same way to create complex patterns from differently layouted uvs onto the same texture. This way you won't run into texel density issues, no matter how many variations you need. As you can see, different patterns can even be aligned along each other.

**Keep in mind you will get baking issues if you intend to bake additional maps like AO since the UVs overlap.**

#### Modeling

##### Spirals / Tubes / Pipes

![](../../_media/modding/general/polycount_spirals.png)Pipes, Tubes and spiraling wires are common elements of vehicles. They tend to increase the polycount quite a bit and should be used with caution. Especially when being constructed procedurally by spiral objects or spline curves in your content creation tool, they can have more polygons than necessary. Often a way lower polycount is enough while still looking good from a reasonable distance. Keep in mind even LOD0 should be game-ready, which means small wires don't need to have so much resolution that they still look smooth when zoomed in full-screen. Most of the time they will be seen from a humanly reasonable distance and that's the distance where the resolution should suffice.

**Especially the number of segments for the curve profile (the "base circle" of such spirals) increase the polycount quite a bit since it scales wih the length of the whole curve. Often, shading these curve smoothly is a better tradeoff compared to more polygons for the curve profile.**

##### Bevels and Smooth Shading

![](../../_media/modding/general/polycount_bevels.png)In reality, perfectly sharp edges are almost non-existent and smoothing edges a bit can be an important tool to convey a realistic feeling of surfaces. Especially for modern technical objects like vehicles, they are quite common. Unfortunately, if we just subdivide surfaces for perfect smoothness, this blows up the polycount quite fast. Luckily, there are some tricks to prevent this.

**Smooth shaded edges can convincingly make surfaces look more detailed than they actually are.** In many cases, a rounded edge with only two subdividion loops will provide the same visual quality as a comparably much more subdivided edge.

**It's best practice to start with lower subdivisions** and keep track of the polycount, since it can increase very fast with just a couple more subdivisions, depending on the complexity of the model. Even for this simple cube, you can see how fast the polycount increased, with just a tiny bit more accentuated smoothing gained from it.

**If you still want to sharpen the edge a bit more, you can use Blenders Bevel Node and bake a normal map without having to increase the polycount further.**

##### Glass Sorting

![](../../_media/modding/general/glass_sorting.png)Correctly sorting overlapping transparencies can be a challenge even for modern game engines. In general, **transparencies are not sorted per pixel like conventional opaque geometry, but per object.** And triangles inside a single geometry are sorted by their index, if no other factor (for example a setting in the submaterial) sorts them differently. **This will become a problem if we can see one transparent objects from different sides and transparent surfaces overlap each other in different ways.** Then it will look like some parts are drawn above others, even if spacially the overlap differently.

Knowing this, we can help the game engine sort our transparencies correctly by **providing additional pivot points for sorting**. This can simply be done by splitting one object into separate ones and centering the pivot. The game engine will then calculate the distance from these objects to the camera based on the current view and sort our objects accordingly. **This way, it will look correct from all angles.**

**Keep in mind: Splitting objects creates additional Draw Calls!** It's often not necessary to split every single glass, but rather keep all those glass triangles in a single object that can't overlap each other anyway.

![](../../_media/modding/general/glass_vehicles.png)A good rule of thumb would be for vehicles: left windows, right windows, front windows, back windows.

There are some setups that can break this approach, like doors which are movable/animated as well as overlapping glass windows due to the design of a vehicle. For example some trains have a pretty curved front where multiple parts of the cabin can intersect perspectively. In this case, it should be split into multiple objects that are coplanar to each other, meaning they form a single flat plane.

**→ roughly 9 Draw Calls in total for all the glass on the vehicle.**

##### Map Baking and UV Transfer

![](../../_media/modding/general/uv_projection_baking.png)Sometimes you'll want to repeat patterns along a surface and triplanar projection or regular uvs are not an option. In these cases you can use additional uv sets to layout your texture and project the result back to your regular UVs. It's very easy to do in Substance Painter:

1. Create your additional UV in your content creation software
2. Set the projection method in SP to "UV set to UV set projection".
3. Select the uv you want to project from. It can be anything except uv0.
4. This way you can also use multiple different UV sets for different parts of your model, or even different material layers on the same polygons.

### Model Editor

#### Lights

Rendering lights tends to be among the more costy processes of rendering in games. Both the light count and the light range are the two parameters that can drastically impact light performance. To keep performance impact of an asset low, there shouldn't be too many individual light sources per asset, and overall lights shouldn't be too large.

##### Vehicles

![](../../_media/modding/general/light_sources_vehicles.png)Vehicles tend to have quite a lot of lights that increase their bounding box quite a bit. A larger bounding box means the vehicle will be rendered longer, even if its already out of screen.

Some good rules of thumb for vehicles (especially trains):

- the max light range should be no larger than 2x the length of a regular train, which is around 32 units
- Longer trains don't necessarily need longer-ranged lights
- Lights should be parented to their visual light-emitting objects so they are properly disabled via animations
- Often a reason for longer ranged lights is to increase brightness or get a smoother falloff. Try to experiment with the light strength, it should still give good results sticking to these guidelines.
- Tilting the cone a bit more to the floor or sky can influence brightness and falloff in positive way
- Lights should be disabled at some distance for lower lods.

##### Buildings

![](../../_media/modding/general/light_sources_buildings.png)Buildings can be more difficult to light compared to vehicles since its a very individual process. The guideline constraints remain the same though: try to minimize light count and range. It can get quite cumbersome to represent every light-emitting object in your building with its own light source. Approximations might make the setup cleaner, better performing and provide the same visual fidelity.

- The game has many different light types, use the shapes appropriate for your case
- Try to find a good balance between enough lights for contrast/atmosphere and not too many that make the setup noisy and performance-heavy
- Mode:ABSORBER lights can be used to darken areas and enhance contrast / atmosphere
- If you just need surfaces to be brighter and don't need to illuminate other objects, you can also use emissive materials with a mask

## Some Final Tips

- Actively use the draw call / polycount stats panel in the Model Editor
- Test cBlend where applicable, generate all icons and check ingame
- Use the validator actively in the process
- Base Level of Weathering is highly encouraged to fit with other ingame assets
- Files and node names should use lower case letters
