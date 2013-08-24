local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'

local Rect = require 'Rect'
local Timer = require 'Timer'
local DynO = require 'DynO'

local screen_rect = Rect(0, 0, screen_width, screen_height)

local function leaving_screen(pos, vel)
   if screen_rect:contains(pos) then
      return false
   else
      if (pos[1] < screen_rect.minx and vel[1] < 0) or
         (pos[1] > screen_rect.maxx and vel[1] > 0) or
         (pos[2] < screen_rect.miny and vel[2] < 0) or
         (pos[2] > screen_rect.maxy and vel[2] > 0) then
         return true
      else
         return false
      end
   end
end

Photon = oo.class(DynO)

function Photon:init(pos, vel)
   DynO.init(self, pos)

   local go = self:go()
   go:vel(vel)
   go:fixed_rotation(0)
   go:angle(vel:angle())

   local _art = world:atlas_entry(constant.ATLAS, 'photon')
   local w = _art.w
   local h = _art.h
   go:add_component('CColoredSprite', {entry=_art, w=2*w, h=2*h})
   go:add_component('CSensor', {fixture={type='rect', w=2*w, h=2*h}})
end

function Photon:update()
   local go = self:go()
   go:angle(vector.new(go:vel()):angle())
   if leaving_screen(go:pos(), go:vel()) then
      self:terminate()
   end
end

function Photon:colliding_with(other)
end

local czor = world:create_object('Compositor')

function background()
   czor:clear_with_color(util.rgba(255,255,255,255))
end

function level_init()
   util.install_basic_keymap()
   world:gravity({0,0})

   local cam = stage:find_component('Camera', nil)
   cam:pre_render(util.fthread(background))

   local timer = nil
   local spawner = nil
   local spawn_rate = 100

   spawner = function()
      Photon(screen_rect:center(), util.rand_vector(100, 200))
      timer:reset(util.rand_exponential(spawn_rate), spawner)
   end
   timer = Timer()
   timer:reset(util.rand_exponential(spawn_rate), spawner)
end
