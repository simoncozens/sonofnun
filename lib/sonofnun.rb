
require 'mongoid'
require 'ostruct'
require 'active_support'
require 'mongoid/geospatial'
require 'rgeo'
require 'rgeo-geojson'

ENV["MONGOID_ENV"] = "development"
Mongoid.load!("mongoid.yml")

SIGNIFICANCE = 100_000 # People
UNREACHED_PERCENT = 5.0

EARTH_RADIUS = 3958 # Miles

def deg2rad(x)
  return Math::PI / 180 * x
end

class Religion
  include Mongoid::Document
  include Mongoid::Attributes::Dynamic
  def name
    self.PrimaryReligion
  end
end

class Country
  include Mongoid::Document
  include Mongoid::Attributes::Dynamic
  include Mongoid::Geospatial
  has_many :people_groups
  has_many :communities
  def self.called(x)
    Country.where( Ctry: x ).first
  end
  def name
    self.Ctry
  end
  def evangelical_percentage
    return self.OWPctEvang if has_attribute?("OWPctEvang")
    return communities.sum(:EvangelicalPopulation) / communities.sum(:LocalPopl).to_f
  end

  def unreached?
    return evangelical_percentage < UNREACHED_PERCENT
  end

  def polygons
    wgs_84_factory = RGeo::Geographic.spherical_factory()
    cg = self.geometry
    cpolys = []
    json_geom = RGeo::GeoJSON.decode(cg.as_json, geo_factory: wgs_84_factory, json_parser: :json)
    if json_geom.respond_to?(:each)
      json_geom.each do |geom|
        cpolys.append(geom.exterior_ring.points.map {|p| [p.x, p.y] })

      end
    else
      cpolys.append(json_geom.exterior_ring.points.map {|p| [p.x, p.y] })
    end
    return cpolys
  end
end

class PeopleGroup
  include Mongoid::Document
  include Mongoid::Attributes::Dynamic
  has_many :communities
  def name
    self.PeopName
  end

  def home_country
    if respond_to?(:country_idLargest)
      @home_country ||= Country.where(country_id: country_idLargest).first
    end
    return @home_country
  end

  def main_community
    @main_community ||= home_country.communities.where(people_group_id: id).first
  end
end

class Community
  include Mongoid::Document
  include Mongoid::Attributes::Dynamic
  include Mongoid::Geospatial
  field :location, type: Point, sphere: true
  belongs_to :country
  belongs_to :people_group

  def self.sizable
    where(:population.gt => SIGNIFICANCE)
  end

  def self.diaspora
    where(:is_diaspora => true)
  end

  def self.significant_evangelical_populations
    where(:EvangelicalPopulation.gt => SIGNIFICANCE)
  end

  def self.unreached
    where(:EvangelicalPercentage.lt => UNREACHED_PERCENT)
  end

  def unreached?
    return EvangelicalPercentage < UNREACHED_PERCENT
  end

  def name
    people_group.name + " of " + country.name
  end

  def distance(other)
    if not self.location or not other.location
      return 0.0 / 0.0 # NaN
    end
    dLat = deg2rad(other.Latitude - self.Latitude)
    dLon = deg2rad(other.Longitude - self.Longitude)
    a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(deg2rad(self.Latitude)) * Math.cos(deg2rad(other.Latitude)) * Math.sin(dLon/2) * Math.sin(dLon/2)
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    return EARTH_RADIUS * c
  end

  def power_ratio(other)
    evs = self.EvangelicalPopulation || 0
    target = other.PopulationRounded || 0
    return (target/evs.to_f) / distance(other)
  end

  def ratio_evangelicals_to_surrounding_country
    return self.EvangelicalPercentage / self.country.evangelical_percentage
  end

  def ratio_evangelicals_to_home_community
    return self.EvangelicalPercentage / self.people_group.main_community.EvangelicalPercentage
  end

  def can_impact_surrounding_country?
    return false if self.EvangelicalPopulation < 100
    return ratio_evangelicals_to_surrounding_country > 2
  end

  def can_impact_home_community?
    return false if not is_diaspora
    return false if not self.people_group.main_community
    return ratio_evangelicals_to_home_community > 2
  end

end