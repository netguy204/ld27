-- supporting functions. loaded directly into the global namespace
-- because they're used so frequently

local constant = require 'constant'
local util = require 'util'

local Rect = require 'Rect'

font = nil
screen_rect = Rect(0, 0, screen_width, screen_height)


local sfx = {}

function load_sfx(kind, names)
   sfx[kind] = {}
   for ii, name in ipairs(names) do
      table.insert(sfx[kind], world:get_sound(name, 1.0))
   end
end

function play_sfx(kind)
   local snd = util.rand_choice(sfx[kind])
   world:play_sound(snd, 1)
end

function default_font()
   if not font then
      local characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!?,\'"'
      font = world:create_object('Font')
      font:load(world:atlas(constant.ATLAS), 'visitor', characters)
      font:scale(3)
      font:set_char_width('i', 3)
      font:set_char_lead('i', -2)
      font:set_char_width('.', 3)
      font:set_char_lead('.', -2)
      font:set_char_width(',', 3)
      font:set_char_lead(',', -3)
      font:word_separation(5)
   end
   return font
end

function toroid_wrap(go)
   local pos = go:pos()
   local change = 0
   -- if we're leaving the screen, wrap us back around
   if not screen_rect:contains(pos) then
      if pos[1] > screen_rect.maxx then
         pos[1] = 0.1
         change = 1
      elseif pos[1] < screen_rect.minx then
         pos[1] = screen_rect.maxx - 0.1
         change = -1
      end
      if pos[2] > screen_rect.maxy then
         pos[2] = screen_rect.miny + 0.1
      elseif pos[2] < screen_rect.miny then
         pos[2] = screen_rect.maxy - 0.1
      end
      go:pos(pos)
      return change
   end
   return change
end

local function star_flame(go)
   local _art = world:atlas_entry(constant.ATLAS, 'fire')
   local params =
      {def=
          {layer=constant.BACKGROUND,
           n=1000,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_art}},
           activator={name='PSConstantRateActivator',
                      params={rate=10000}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0,10}}},
              {name='PSTimeAlphaUpdater',
               params={time_constant=0.3,
                       max_scale=6.0}},
              {name='PSFireColorUpdater',
               params={max_life=0.5,
                       start_temperature=9000,
                       end_temperature=500}},
              {name='PSBoxInitializer',
               params={initial={0,0,screen_width,0},
                       refresh={0,0,screen_width,0},
                       minv={-100,100},
                       maxv={100,300}}},
              {name='PSTimeInitializer',
               params={min_life=0.3,
                       max_life=0.6}},
              {name='PSTimeTerminator'}}}}

   return go:add_component('CParticleSystem', params)
end

local star_particles = nil

function enable_star_particles()
   if not star_particles then
      star_particles = star_flame(stage)
   end
end

function disable_star_particles()
   if star_particles then
      star_particles:delete_me(1)
   end
   star_particles = nil
end
