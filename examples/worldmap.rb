#/usr/bin/ruby -Ilib

# This file draws a world map, colorizes the countries based on
# the percentage of the population that is Evangelical, and
# then draws lines between significant evangelical communities
# who are living nearby significant unreached communities.

require 'sonofnun'
require 'victor' # SVG generation library

NEARBY = 300.0 # miles

svg = Victor::SVG.new width: 1000, height: 1000, style: { background: '#fff' }

# Scale and shift the map
def convert_point(x)
  return [3*x[0]+400,-3*x[1]+300]
end

# Watch out for countries that wrap around the X axis!
def dont_wrap(pts)
  xavg = pts.map{|x|x[0]}.sum / pts.length
  return pts if xavg < 450
  xmax = pts.map{|x|x[0]}.max
  return pts.map{|x| [ (x[0] < 100 ? xmax : x[0]), x[1] ]}
end

# Illustrator hates HSV
def hsv_to_rgb(h, s, v)
  h, s, v = h.to_f/360, s.to_f/100, v.to_f/100
  h_i = (h*6).to_i
  f = h*6 - h_i
  p = v * (1 - s)
  q = v * (1 - f*s)
  t = v * (1 - (1 - f) * s)
  r, g, b = v, t, p if h_i==0
  r, g, b = q, v, p if h_i==1
  r, g, b = p, v, t if h_i==2
  r, g, b = p, q, v if h_i==3
  r, g, b = t, p, v if h_i==4
  r, g, b = v, p, q if h_i==5
  [(r*255).to_i, (g*255).to_i, (b*255).to_i]
end

# Colorize a country based on its percentage Evangelicals
# Use a log scale of redness (0% = completely red, 100% = white)
def color(pc)
  return "rgb(170,170,20)" if pc.nan?
  pcAdj = (100 - 100*Math.log(0.1+pc,10)).to_i.clamp(0,100)
  return "rgb("+hsv_to_rgb(0,pcAdj,70).map(&:to_s).join(",")+")"
end

svg.build do
  puts("Drawing countries")
  Country.where(:geometry.ne =>nil).each do |c|
    ccolor = color(c.evangelical_percentage)
    c.polygons.each do |pts|
      pts = dont_wrap(pts.map {|x| convert_point(x) })
      polygon points: pts.flatten, style: { stroke: "#aaa", fill: ccolor }
    end
  end

  puts("Drawing communities")
  done = {}

  Community.significant_evangelical_populations.each do |ev_community|

    reached_loc = convert_point([ev_community.Longitude, ev_community.Latitude])

    unreached_communities = Community.sizable.unreached
                            .near_sphere(location: ev_community.location)
                            .max_distance(location: NEARBY / 3963.0)

    if unreached_communities.count > 0
      # Draw a dot for the Evangelical community
      circle cx: reached_loc[0], cy: reached_loc[1],
             r:2, fill: ev_community.is_diaspora ? "green" : "yellow"

      # And now dots and lines to each nearby unreached one
      unreached_communities.each do |un|
        unreached_loc = convert_point([un.Longitude, un.Latitude])
        circle cx: unreached_loc[0], cy: unreached_loc[1],
               r:2, fill: "red" if not done[un.id]
        line x1: reached_loc[0],   y1: reached_loc[1],
             x2: unreached_loc[0], y2: unreached_loc[1],
             stroke: "rgba(0,0,0,0.1)"
        done[un.id] = true
      end
    end
  end
end

svg.save "world"