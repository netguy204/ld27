local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'

local Rect = require 'Rect'
local Timer = require 'Timer'
local DynO = require 'DynO'
local Indicator = require 'Indicator'

require 'support'

local player_indicator = nil
local player = nil
local player_last_stats = {}
local session_stats = {}
local session_last_play_stats = nil
local next_level = 1
local current_level = 0
local story_played = false
local background_color = {0,0,0,1}
local level_seed = 0

local trails = {}

local level_teardown = function()
end

local level_running_test = function()
   return false
end

-- speed of light... for our purposes
local c = 1000
local function gamma(spd)
   -- make sure we return a real number
   spd = math.min(spd, c * 0.9999)
   return 1 / math.sqrt(1 - (spd * spd) / (c * c))
end

function dist2au(dist)
   return dist * 3e6 / 150e9
end

local function leaving_screen(pos, vel)
   if screen_rect:contains(pos) then
      return false
   else
      if vector.length(vel) < 0.001 then
         return false
      elseif (pos[1] < screen_rect.minx and vel[1] < 0) or
         (pos[1] > screen_rect.maxx and vel[1] > 0) or
         (pos[2] < screen_rect.miny and vel[2] < 0) or
         (pos[2] > screen_rect.maxy and vel[2] > 0) then
         return true
      else
         return false
      end
   end
end

Source = oo.class(DynO)

function Source:init(pos, kind, sink)
   DynO.init(self, pos)
   self.timer = Timer()
   self.rate = 10
   self.kind = kind
   self.sink = sink
   self.timer:reset(util.rand_exponential(self.rate), self:bind('spawn'))

   local go = self:go()
   local _art = world:atlas_entry(constant.ATLAS, 'goodie_source')
   local w = _art.w * 2
   local h = _art.h * 2
   go:add_component('CColoredSprite', {entry=_art, w=w, h=h})
end

function Source:spawn()
   local go = self:go()
   if not go then return end

   self.kind.make(go:pos(), self.sink)
   self.timer:reset(util.rand_exponential(self.rate), self:bind('spawn'))
end

local Sink = oo.class(DynO)

function Sink:init(pos)
   DynO.init(self, pos)
end

local Photon = oo.class(DynO)

function Photon:init(pos, vel, sink, image)
   DynO.init(self, pos)

   self.sink = sink
   local go = self:go()
   go:vel(vel)
   go:fixed_rotation(0)

   local _art = world:atlas_entry(constant.ATLAS, image)
   local w = _art.w
   local h = _art.h
   self.sprite = go:add_component('CColoredSprite', {entry=_art, w=2*w, h=2*h})
   go:add_component('CSensor', {fixture={type='rect', w=2*w, h=2*h}})

   local seeker = world:create_object('SeekBrain')
   seeker:tgt(sink:go():pos())
   seeker:params({force_max = 50000,
                  speed_max = vector.length(vel),
                  old_angle = 0,
                  application_time = world:dt()})
   self.brain = self:go():add_component('CBrain', {brain=seeker})
end

function Photon:update()
   local go = self:go()
   if not go then return end

   go:angle(vector.new(go:vel()):angle())
   if leaving_screen(go:pos(), go:vel()) then
      self:terminate()
   end
end

local EnergeticPhoton = oo.class(Photon)
local SlowPhoton = oo.class(Photon)

EnergeticPhoton.min_speed = 300
EnergeticPhoton.max_speed = 500
SlowPhoton.min_speed = 100
SlowPhoton.max_speed = 300

function EnergeticPhoton:init(pos, vel, sink)
   Photon.init(self, pos, vel, sink, 'energetic_photon')
end

function EnergeticPhoton.make(pos, sink)
   return EnergeticPhoton(pos, util.rand_vector(EnergeticPhoton.min_speed, EnergeticPhoton.max_speed), sink)
end

function SlowPhoton:init(pos, vel, sink)
   Photon.init(self, pos, vel, sink, 'slow_photon')
   self.sprite:angle_offset(math.pi)
end

function SlowPhoton.make(pos, sink)
   return SlowPhoton(pos, util.rand_vector(SlowPhoton.min_speed, SlowPhoton.max_speed), sink)
end

local czor = world:create_object('Compositor')

function background()
   czor:clear_with_color(background_color)
end

local function player_streak(go)
   local _art = world:atlas_entry(constant.ATLAS, 'photon')
   local params =
      {def=
          {layer=constant.BACKGROUND,
           n=20,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_art}},
           activator={name='PSConstantRateActivator',
                      params={rate=10}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0,0}}},
              {name='PSTimeAlphaUpdater',
               params={time_constant=3.0,
                       max_scale=4.0}},
              {name='PSFireColorUpdater',
               params={max_life=2,
                       start_temperature=9000,
                       end_temperature=500}},
              {name='PSBoxInitializer',
               params={initial={0,0,0,0},
                       refresh={0,0,0,0},
                       minv={0,0},
                       maxv={0,0}}},
              {name='PSTimeInitializer',
               params={min_life=2,
                       max_life=2}},
              {name='PSTimeTerminator'}}}}

   return go:add_component('CParticleSystem', params)
end

local Player = oo.class(DynO)

function Player:init(pos, vel)
   DynO.init(self, pos)
   self.max_speed = 300
   self.max_delta_speed = 1000
   self.current_screen = 1
   self.trail = {}
   self._trail = world:atlas_entry(constant.ATLAS, 'trail')

   local go = self:go()
   go:vel(vel)
   go:fixed_rotation(0)

   local _art = world:atlas_entry(constant.ATLAS, 'photon')
   local w = _art.w * 2
   local h = _art.h * 2
   go:add_component('CColoredSprite', {entry=_art, w=w, h=h})
   go:add_component('CSensor', {fixture={type='rect', w=w, h=h, density=10}})

   player_streak(go)
   self:set_screen(1)
end

function Player:add_trail_component(item)
   local w = self._trail.w * 2 * item.scale
   local h = self._trail.h * 2 * item.scale
   local comp = stage:add_component('CColoredSprite', {entry=self._trail, w=w, h=h,
                                                       angle_offset=item.angle,
                                                       offset=item.pos, color=item.color})
   table.insert(self.trail, comp)
end

function Player:world_trail()
   if not trails[current_level] then
      trails[current_level] = {}
   end
   if not trails[current_level][self.current_screen] then
      trails[current_level][self.current_screen] = {}
   end
   return trails[current_level][self.current_screen]
end

function Player:set_screen(screen)
   self.current_screen = screen
   for ii, item in ipairs(self.trail) do
      item:delete_me(1)
   end
   self.trail = {}

   -- pull in our last pass through this screen
   for ii, item in ipairs(self:world_trail()) do
      self:add_trail_component(item)
   end
end

function Player:update()
   local go = self:go()
   if not go then return end

   local pos = vector.new(go:pos())
   local vel = vector.new(go:vel())
   local angle = vector.new(go:vel()):angle()
   go:angle(angle)

   local dist = self.dist or 0
   self.dist = dist + vel[1] * world:dt()

   local input = util.input_state()
   local updown = input.updown
   if updown == 0 then
      updown = -input.leftright
   end

   -- adjust updown vel if buttun is pressed
   local yspd_adj = updown * self.max_delta_speed * world:dt()
   if math.abs(yspd_adj + vel[2]) > self.max_speed then
      -- cap the speed
      yspd_adj = util.sign(vel[2]) * self.max_speed - vel[2]
   end
   local vel_adj = vector.new({0, yspd_adj})

   go:apply_impulse(vel_adj * go:mass())

   local screen_change = toroid_wrap(go)
   if not (screen_change == 0) then
      -- update the visible trail
      self:set_screen(self.current_screen + screen_change)
   end

   local trail_spacing = 20
   local last_dist = self.last_dist or 0
   local new_dist = math.floor((self.dist or 0) / trail_spacing)
   if not (new_dist == last_dist) then
      local item = {pos=pos, color={1,1,1,0.5}, angle=angle, scale=1}
      self:add_trail_component(item)
      table.insert(self:world_trail(), item)
   end
   self.last_dist = new_dist

   self:update_indicators()
end

function Player:terminate()
   local go = self:go()
   local pos = go:pos()
   table.insert(self:world_trail(), {pos=pos, color={1,1,0,0.5}, scale=2, angle=0})

   DynO.terminate(self)
   for ii, item in ipairs(self.trail) do
      item:delete_me(1)
   end
end

function Player:colliding_with(other)
   if other:is_a(Photon) then
      local go = self:go()
      local vel = vector.new(go:vel())

      local veladj = nil

      if other:is_a(EnergeticPhoton) then
         veladj = vector.new({150, 0})
         play_sfx('goodie')
      elseif other:is_a(SlowPhoton) then
         veladj = vector.new({-100, 0})
         play_sfx('baddie')
      end

      local newvel = vel + veladj

      -- don't let us go too slow
      if newvel[1] < 100 then
         veladj[1] = 100 - vel[1]
      end

      -- apply the adjustment using the gamma of the proposed final
      -- velocity
      local invgamma = 1 / gamma(math.abs(vel[1]))
      veladj = veladj * invgamma

      other:terminate()
      go:apply_impulse(veladj * go:mass())
   end
end

function Player:stats()
   local go = self:go()
   local speed = go:vel()[1]
   local best_speed = speed
   if player_last_stats.best_speed then
      best_speed = math.max(player_last_stats.best_speed, speed)
   end

   return {speed = speed,
           distance = self.dist,
           best_speed = best_speed}
end

local DemoPlayer = oo.class(Player)

function DemoPlayer:init(pos, vel)
   Player.init(self, pos, vel)

   local go = self:go()
   local seeker = world:create_object('SeekBrain')
   seeker:tgt({screen_width, screen_height/2})
   seeker:params({force_max = 50000,
                  speed_max = vector.new(vel):length(),
                  old_angle = 0,
                  application_time = world:dt()})
   go:add_component('CBrain', {brain=seeker})
end

function DemoPlayer:update()
   local go = self:go()
   if not go then return end

   go:angle(vector.new(go:vel()):angle())
   toroid_wrap(go)
end

function DemoPlayer:update_indicators()
   -- no indicators
end


local L1Player = oo.class(Player)

function L1Player:update_indicators()
   -- update our speed indicator
   local go = self:go()
   if not go then return end

   local vel = go:vel()
   player_indicator:update('Speed  %.4f c', vel[1] / c)
end

local L2Player = oo.class(Player)

function L2Player:update()
   Player.update(self)

   -- apply an additional drag force
   local go = self:go()
   if not go then return end

   local vel = vector.new(go:vel())
   local drag = 0.01
   local drag_force = vel:norm() * (-drag)
   go:apply_force(drag_force)
end

function L2Player:update_indicators()
   local go = self:go()
   if not go then return end

   player_indicator:update('Distance  %.2f au', dist2au(self.dist))
end

local Rock = oo.class(DynO)

function Rock:init(pos, vel, spin_rate)
   DynO.init(self, pos)

   local go = self:go()
   go:fixed_rotation(0)
   go:vel(vel)
   go:angle_rate(spin_rate)

   local _art = world:atlas_entry(constant.ATLAS, 'rock1')
   local w = 2*_art.w
   local h = 2*_art.h
   local r = math.sqrt(w*w + h*h) * 0.3

   go:add_component('CColoredSprite', {entry=_art, w=w, h=h})
   go:add_component('CSensor', {fixture={type='circle', radius=r, density=100}})
end

function Rock:update()
   local go = self:go()
   if not go then return end

   toroid_wrap(go)
end

function indicators()
   local color = {1,1,1,0.6}
   player_indicator = Indicator(font, {screen_width/2, screen_height - font:line_height()/2}, color)
   time_indicator = Indicator(font, {screen_width/2, screen_height - font:line_height()*3/2}, color)
end

function level_timer()
   local time_update_period = 0.1
   local time_remaining = 10
   local time_timer = Timer()
   local time_updater = nil
   time_updater = function()
      local go = player:go()
      if not go then return end

      local vel = vector.new(go:vel())
      local spd = vel:length()
      time_remaining = time_remaining - time_update_period / gamma(spd)
      local dilation = 1 - 1/gamma(spd)
      time_indicator:update('Time Remaining %.1f', time_remaining)
      if time_remaining > 0 then
         time_timer:reset(time_update_period, time_updater)
      end
   end
   time_updater()

   -- return a function that will determine if the level is complete
   local complete = function()
      return time_remaining > 0
   end
   return complete
end

function make_background()
   return background_stars(stage)
end

function screen_sequence(fns, ...)
   local args = {...}
   local trigger = util.rising_edge_trigger(false)
   local count = util.count(fns)
   local current = 1

   fns[current](table.unpack(args))
   local thread = function(go, comp)
      while true do
         coroutine.yield()
         local input = util.input_state()
         if trigger(input.action1) then
            current = current + 1
            fns[current](table.unpack(args))
            if current == count then
               return
            end
         end
      end
   end

   if count > 1 then
      return stage:add_component('CScripted', {update_thread=util.thread(thread)})
   end
end

function make_story(seq)
   local text = Indicator(font, {screen_width/2, screen_height - font:line_height() * 2}, {1,1,1,1})

   local press = 'Press Z'
   local press_pos = vector.new({screen_width / 2, font:line_height()})
   local press_black = Indicator(font, press_pos, {0,0,0,1})
   local press_white = Indicator(font, press_pos + vector.new({0,-2}), {1,1,1,1})
   press_black:update(press)
   press_white:update(press)

   local text_chunk = function(str)
      local fn = function()
         text:update(str)
      end
      return fn
   end

   local ctrl = {
      text_chunk = text_chunk,
      running = true
   }

   local comp = screen_sequence(seq, ctrl)

   level_running_test = function()
      return ctrl.running
   end

   level_teardown = function()
      Indicator.terminate_all()
      comp:delete_me(1)
   end
end

function story()
   local story = {
      [[Life of a Photon]],

      [[I was born in star. I was young and full of hope.]],

      [[My cousins were supportive. We were heading in the same direction.]],

      [[There were others who tried to stand in the way.]],

      [[Though there would be challenges, it was time to pick up speed.]]
   }

   local sink = nil
   local spawner = nil
   local demo_player = DemoPlayer({screen_width/2, screen_height/2}, {200,0})

   local seq = {
      function(ctrl)
         ctrl.text_chunk(story[1])()
      end,
      function(ctrl)
         ctrl.text_chunk(story[2])()
      end,
      function(ctrl)
         ctrl.text_chunk(story[3])()
         sink = Sink({screen_width, screen_height/2})
         spawner = Source({screen_width/2, screen_height/2}, EnergeticPhoton, sink)
      end,
      function(ctrl)
         ctrl.text_chunk(story[4])()
         sink:terminate()
         spawner:terminate()

         sink = Sink({0, screen_height/2})
         spawner = Source({screen_width/2, screen_height/2}, SlowPhoton, sink)
      end,
      function(ctrl)
         ctrl.text_chunk(story[5])()
         sink:terminate()
         spawner:terminate()
         DynO.terminate_all(SlowPhoton)
      end,
      function(ctrl)
         demo_player:terminate()
         ctrl.running = false
      end
   }

   make_story(seq)
   enable_star_particles()
end

function launch_story()
   local story = {
      [[I soared out of the stellar nursery and into the vastness of space.]],

      [[There I encountered objects that were far more massive than I.]],

      [[I knew that I shouldnt get too close. They would only sap my energy.]]
   }

   local demo_player = nil
   local seq = {
      function(ctrl)
         if story_played then
            ctrl.running = false
         else
            demo_player = DemoPlayer({0.1, screen_height/2}, {player_last_stats.speed, 0})
            ctrl.text_chunk(story[1])()
         end
      end,
      function(ctrl)
         for x=1,3 do
            for y=1,2 do
               local rspin = util.rand_between(-2*math.pi*0.3, 2*math.pi*0.3)
               Rock({screen_width * x / 4, screen_height * y / 3}, {0,0}, rspin)
            end
         end
         ctrl.text_chunk(story[2])()
      end,
      function(ctrl)
         ctrl.text_chunk(story[3])()
      end,
      function(ctrl)
         ctrl.running = false
         story_played = true
         demo_player:terminate()
         DynO.terminate_all()
      end
   }

   make_story(seq)
   disable_star_particles()
end

function finish_story()
   local story = {}
   if (player_last_stats.best_speed / c) < 0.3 then
      table.insert(story, [[In spite of my best efforts, I never really picked up speed.]])
   elseif (player_last_stats.best_speed / c) < 0.6 then
      table.insert(story, [[I made good time through the trials of life.]])
   elseif (player_last_stats.best_speed / c) < 0.8 then
      table.insert(story, [[In the end, I was known as one of the quickest and brightest.]])
   else
      table.insert(story, [[Nothing in the universe could match my speed.]])
   end

   if dist2au(player_last_stats.distance) < 0.05 then
      table.insert(story, [[Sad to say, my life didnt go far.]])
   elseif dist2au(player_last_stats.distance) < 0.1 then
      table.insert(story, [[I didnt settle far from home, but it was a good trip.]])
   elseif dist2au(player_last_stats.distance) < 0.2 then
      table.insert(story, [[I reached for the stars and really almost made it.]])
   else
      table.insert(story, [[No one I know has ever seen what Ive seen.]])
   end

   local seq = {
      function(ctrl)
         ctrl.text_chunk(story[1])()
      end,
      function(ctrl)
         ctrl.text_chunk(story[2])()
      end,
      function(ctrl)
         ctrl.running = false
      end
   }

   make_story(seq)
end

function level1()
   math.randomseed(level_seed)

   local esink_pos = {screen_width, util.rand_between(screen_height/6, screen_height*5/6)}
   local esource_pos = {util.rand_between(screen_width/3, screen_width*2/3),
                        util.rand_between(screen_height/3, screen_height*2/3)}
   local energetic_sink = Sink(esink_pos)
   local energetic_spawner = Source(esource_pos, EnergeticPhoton, energetic_sink)

   local ssink_pos = {0, util.rand_between(screen_height/6, screen_height*5/6)}
   local ssource_pos = {util.rand_between(screen_width/3, screen_width*2/3),
                        util.rand_between(screen_height/3, screen_height*2/3)}
   local slow_sink = Sink(ssink_pos)
   local slow_spawner = Source(ssource_pos, SlowPhoton, slow_sink)
   slow_spawner.rate = 4

   player = L1Player({0.1, screen_height/2}, vector.new({200, 0}))
   indicators()

   level_running_test = level_timer()
   level_teardown = function()
      player_last_stats = player:stats()
      Indicator.terminate_all()
      DynO.terminate_all()
   end

   enable_star_particles()
end

function level2()
   math.randomseed(level_seed)

   -- scatter some rocks
   local nrocks = 5
   for ii=1,nrocks do
      local rpos = vector.new({util.rand_between(screen_width/3, screen_width*2/3),
                               util.rand_between(screen_height/3, screen_height*2/3)})
      local rvel = util.rand_vector(100, 200)
      local rspin = util.rand_between(-2*math.pi*0.3, 2*math.pi*0.3)
      Rock(rpos, rvel, rspin)
   end

   -- launch the player with their previous stats, launch at the top
   -- so they'll be safe for a little while
   player = L2Player({0.1, screen_height*4/5}, vector.new({player_last_stats.speed, 0}))

   indicators()

   level_running_test = level_timer()
   level_teardown = function()
      player_last_stats = player:stats()
      Indicator.terminate_all()
      DynO.terminate_all()
   end

   disable_star_particles()
end

function level_end()
   -- update our session stats
   local new_stats = {
      best_distance=math.max(session_stats.best_distance or 0, player_last_stats.distance),
      best_speed=math.max(session_stats.best_speed or 0, player_last_stats.best_speed)
   }

   local dist_suffix = ''
   if session_stats.best_distance and player_last_stats.distance > session_stats.best_distance then
      dist_suffix = ' (new personal best)'
   end
   local speed_suffix = ''
   if session_stats.best_speed and player_last_stats.best_speed > session_stats.best_speed then
      speed_suffix = ' (new personal best)'
   end

   local color = {1,1,1,1}
   local top = vector.new({screen_width/2, screen_height - font:line_height()})
   local displacement = vector.new({0, -font:line_height()})

   local distance = Indicator(font, top, color)
   local speed = Indicator(font, top + displacement, color)

   distance:update('Distance Traveled  %.3f au%s', dist2au(player_last_stats.distance), dist_suffix)
   speed:update('Speed  %.4f c%s', player_last_stats.best_speed / c, speed_suffix)

   if session_last_play_stats then
      color = {1,1,1,0.5}
      local best_distance = Indicator(font, top + displacement * 3, color)
      local best_speed = Indicator(font, top + displacement * 4, color)
      best_distance:update('Best Distance  %.3f au', dist2au(new_stats.best_distance))
      best_speed:update('Best Speed  %.4f c', new_stats.best_speed / c)
   end

   session_last_play_stats = player_last_stats
   session_stats = new_stats

   local pressz = Indicator(font, {screen_width/2, screen_height/2})
   pressz:update('Press Z to Play Again')

   player_last_stats = {}

   local trigger = util.rising_edge_trigger(true)

   level_running_test = function()
      local input = util.input_state()
      return (not trigger(input.action1))
   end
   level_teardown = function()
      Indicator.terminate_all()
      next_level = 2
   end
end

function init()
   local songs = {'resources/stellar_nursery.ogg'}
   util.loop_music(songs)
   make_background()

   load_sfx('goodie', {'resources/goodie1.ogg'})
   load_sfx('baddie', {'resources/baddie1.ogg'})

   math.randomseed(os.time())
   level_seed = math.random()

   util.install_basic_keymap()
   world:gravity({0,0})

   local cam = stage:find_component('Camera', nil)
   cam:pre_render(util.fthread(background))

   font = default_font()

   local levels = { story, level1, launch_story, level2, finish_story, level_end }

   local level_progression = function()
      if not level_running_test() then
         level_teardown()
         current_level = levels[next_level]
         levels[next_level]()
         next_level = next_level + 1
      end
   end

   stage:add_component('CScripted', {update_thread=util.fthread(level_progression)})
end

function level_init()
   util.protect(init)()
end
