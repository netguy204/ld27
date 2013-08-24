local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'

local Rect = require 'Rect'
local Timer = require 'Timer'
local DynO = require 'DynO'

local screen_rect = Rect(0, 0, screen_width, screen_height)
local font = nil
local player_indicator = nil
local player = nil
local player_last_stats = {speed=100} -- fixme: for testing
local next_level = 1

local level_teardown = function()
end

local level_running_test = function()
   return false
end

local function default_font()
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

-- speed of light... for our purposes
local c = 1000
local function gamma(spd)
   -- make sure we return a real number
   spd = math.min(spd, c * 0.9999)
   return 1 / math.sqrt(1 - (spd * spd) / (c * c))
end

function toroid_wrap(go)
   local pos = go:pos()
   -- if we're leaving the screen, wrap us back around
   if not screen_rect:contains(pos) then
      if pos[1] > screen_rect.maxx then
         pos[1] = 0.1
      elseif pos[1] < screen_rect.minx then
         pos[1] = screen_rect.maxx - 0.1
      end
      if pos[2] > screen_rect.maxy then
         pos[2] = screen_rect.miny + 0.1
      elseif pos[2] < screen_rect.miny then
         pos[2] = screen_rect.maxy - 0.1
      end
      go:pos(pos)
   end
end

function dist2au(dist)
   return dist * 3e6 / 150e9
end

local Indicator = oo.class(oo.Object)

function Indicator:init(font, pos, color)
   self.font = font
   self.pos = pos
   self.text = stage:add_component('CDrawText', {font=font, color=color})
end

function Indicator:update(msg, ...)
   msg = string.format(msg, ...)
   self.text:offset({self.pos[1] - self.font:string_width(msg)/2,
                     self.pos[2] - self.font:line_height()/2})
   self.text:message(msg)
end

function Indicator:terminate()
   self.text:delete_me(1)
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
   go:add_component('CColoredSprite', {entry=_art, w=2*w, h=2*h})
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

local transition_table = nil

function Photon:colliding_with(other)
   if other:is_a(Photon) then
      local transitions = transition_table[getmetatable(self)] or {}
      local newtype = transitions[getmetatable(other)]

      -- 'become' a new type
      if newtype and (not self.cooling) then
         local go = self:go()
         if not go then return end

         newtype.make(go:pos(), self.sink)
         self:terminate()

         local fn = function()
            self.cooling = false
         end
         Timer():reset(1.0, fn)
         self.cooling = true
      end
   end
end

local HyperPhoton = oo.class(Photon)
local EnergeticPhoton = oo.class(Photon)
local SlowPhoton = oo.class(Photon)

transition_table = {
   [HyperPhoton] = { [SlowPhoton] = EnergeticPhoton },
   [EnergeticPhoton] = { [SlowPhoton] = SlowPhoton },
   [SlowPhoton] = { [HyperPhoton] = EnergeticPhoton}
}

HyperPhoton.min_speed = 500
HyperPhoton.max_speed = 600
EnergeticPhoton.min_speed = 300
EnergeticPhoton.max_speed = 500
SlowPhoton.min_speed = 100
SlowPhoton.max_speed = 300

function HyperPhoton:init(pos, vel, sink)
   Photon.init(self, pos, vel, sink, 'hyper_photon')
end

function HyperPhoton.make(pos, sink)
   return HyperPhoton(pos, util.rand_vector(HyperPhoton.min_speed, HyperPhoton.max_speed), sink)
end

function EnergeticPhoton:init(pos, vel, sink)
   Photon.init(self, pos, vel, sink, 'energetic_photon')
end

function EnergeticPhoton.make(pos, sink)
   return EnergeticPhoton(pos, util.rand_vector(EnergeticPhoton.min_speed, EnergeticPhoton.max_speed), sink)
end

function SlowPhoton:init(pos, vel, sink)
   Photon.init(self, pos, vel, sink, 'slow_photon')
end

function SlowPhoton.make(pos, sink)
   return SlowPhoton(pos, util.rand_vector(SlowPhoton.min_speed, SlowPhoton.max_speed), sink)
end

local czor = world:create_object('Compositor')

function background()
   czor:clear_with_color(util.rgba(255,255,255,255))
end

local Player = oo.class(DynO)

function Player:init(pos, vel)
   DynO.init(self, pos)
   self.max_speed = 100
   self.max_delta_speed = 10

   local go = self:go()
   go:vel(vel)
   go:fixed_rotation(0)

   local _art = world:atlas_entry(constant.ATLAS, 'photon')
   local w = _art.w * 2
   local h = _art.h * 2
   go:add_component('CColoredSprite', {entry=_art, w=w, h=h})
   go:add_component('CSensor', {fixture={type='rect', w=w, h=h, density=10}})
end

function Player:update()
   local go = self:go()
   if not go then return end

   local pos = vector.new(go:pos())
   local vel = vector.new(go:vel())
   local angle = vector.new(go:vel()):angle()
   go:angle(angle)

   local input = util.input_state()

   -- adjust updown vel if buttun is pressed
   local yspd_adj = input.updown * self.max_delta_speed
   if yspd_adj + vel[2] > self.max_speed then
      -- cap the speed
      yspd_adj = self.max_speed - vel[2]
   end
   local vel_adj = vector.new({0, yspd_adj})

   go:apply_impulse(vel_adj * go:mass())
   toroid_wrap(go)
   self:update_indicators()
end

function Player:colliding_with(other)
   if other:is_a(Photon) then
      local go = self:go()
      local vel = vector.new(go:vel())

      local veladj = nil

      if other:is_a(EnergeticPhoton) then
         veladj = vector.new({100, 0})
      elseif other:is_a(HyperPhoton) then
         veladj = vector.new({300, 0})
      elseif other:is_a(SlowPhoton) then
         veladj = vector.new({-100, 0})
      end

      local newvel = vel + veladj

      -- don't let us go backwards
      if newvel[1] < 0 then
         veladj[1] = -vel[1]
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
   local vel = go:vel()

   local dist = self.dist or 0
   self.dist = dist + vel[1] * world:dt()

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
   local r = math.sqrt(w*w + h*h) * 0.5

   go:add_component('CColoredSprite', {entry=_art, w=w, h=h})
   go:add_component('CSensor', {fixture={type='circle', radius=r, density=100}})
end

function indicators()
   local color = {1,1,1,0.6}
   player_indicator = Indicator(font, {screen_width/2, screen_height - font:line_height()/2}, color)
   time_indicator = Indicator(font, {screen_width/2, screen_height - font:line_height()*3/2}, color)
   return {player_indicator, time_indicator}
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
      time_indicator:update('Time Remaining  %.3f %.3f', time_remaining, dilation)
      time_timer:reset(time_update_period, time_updater)
   end
   time_updater()

   -- return a function that will determine if the level is complete
   local complete = function()
      return time_remaining > 0
   end
   return complete
end

function make_background()
   local background = world:atlas_entry('resources/background1', 'background1')
   local bw = background.w
   local bh = background.h
   local bg = world:create_go()
   bg:add_component('CStaticSprite', {entry=background})
   bg:pos(screen_rect:center())
   return bg
end

function level1()
   local esink_pos = {screen_width, util.rand_between(screen_height/6, screen_height*5/6)}
   local esource_pos = {util.rand_between(screen_width/3, screen_width*2/3),
                        util.rand_between(screen_height/3, screen_height*2/3)}
   local energetic_sink = Sink(esink_pos)
   local energetic_spawner = Source(esource_pos, HyperPhoton, energetic_sink)

   local ssink_pos = {0, util.rand_between(screen_height/6, screen_height*5/6)}
   local ssource_pos = {util.rand_between(screen_width/3, screen_width*2/3),
                        util.rand_between(screen_height/3, screen_height*2/3)}
   local slow_sink = Sink(ssink_pos)
   local slow_spawner = Source(ssource_pos, SlowPhoton, slow_sink)
   slow_spawner.rate = 4

   local bg = make_background()
   player = L1Player({0.1, screen_height/2}, vector.new({200, 0}))
   local labels = indicators()

   level_running_test = level_timer()
   level_teardown = function()
      player_last_stats = player:stats()
      for ii, label in ipairs(labels) do
         label:terminate()
      end
      local term = function(obj)
         obj:terminate()
      end
      DynO.with_all(term)
      bg:delete_me(1)
   end
end

function level2()
   local bg = make_background()

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

   local labels = indicators()

   level_running_test = level_timer()
   level_teardown = function()
      player_last_stats = player:stats()
      for ii, label in ipairs(labels) do
         label:terminate()
      end
      local term = function(obj)
         obj:terminate()
      end
      DynO.with_all(term)
      bg:delete_me(1)
   end
end

function level_end()
   local labels = indicators()
   player_indicator:update('Distance Traveled  %.3f au', dist2au(player_last_stats.distance))
   time_indicator:update('Best Speed  %.4f c', player_last_stats.best_speed / c)
   player_last_stats = {}
   next_level = 1

   level_running_test = function()
      local input = util.input_state()
      return (not input.action1)
   end
   level_teardown = function()
      for ii, label in ipairs(labels) do
         label:terminate()
      end
   end
end

function init()
   util.install_basic_keymap()
   world:gravity({0,0})

   local cam = stage:find_component('Camera', nil)
   cam:pre_render(util.fthread(background))

   font = default_font()

   local levels = { level1, level2, level_end }

   local level_progression = function()
      if not level_running_test() then
         level_teardown()
         levels[next_level]()
         next_level = next_level + 1
      end
   end

   stage:add_component('CScripted', {update_thread=util.fthread(level_progression)})
end

function level_init()
   util.protect(init)()
end
