#!/usr/bin/ruby -Ilib

require 'CSV'
require 'json'

require 'sonofnun'

people_groups = []
countries = {}
continents =[]
religions = []
people_geographic = {}

def clean(row)
  row = row.to_hash.compact
  return row.except("EditName", "EditDate", "AddDate")#.reject { |k,v| k.include?('_id') }
end

puts("Loading country geometries")
countries_json = JSON.parse(File.read("supplemental/country-simple.geojson"))["features"]
country_map = {}
countries_json.each {|c|
  country_map[c["properties"]["ISO_A3"]] = c["geometry"]
}

puts("Loading religions")
Religion.delete_all
CSV.foreach("original-data/tblRLG3Religions.csv", :headers => true, :converters => :all) do |row|
  Religion.create(row.to_hash.compact)
end

puts("Loading countries and languages")

Country.delete_all
CSV.foreach("original-data/tblGEO3Countries.csv", :headers => true, :converters => :all) do |row|
  row = row.to_hash.compact
  row["geometry"] = country_map[row["ISO3"]]
  Country.create(row.to_hash.compact)
end

languages = {}
CSV.foreach("original-data/tblLNG3Languages.csv", :headers => true, :converters => :all) do |row|
  languages[row["language_id"]] = row["Language"]
end

dialects = []
CSV.foreach("original-data/tblLNG4Dialects.csv", :headers => true, :converters => :all) do |row|
  dialects[row["dialect_id"].to_i] = row["Dialect"]
end

puts("Reading people group definition tables")

PeopleGroup.delete_all
CSV.foreach("original-data/tblPEO3PeopleGroups.csv", :headers => true, :converters => :all) do |row|
  people_groups[row["people_group_id"].to_i] = clean(row)
end

CSV.foreach("original-data/tblPEO4SubGroups.csv", :headers => true, :converters => :all) do |row|
  people_groups[row["people_group_id"].to_i]["SubGroups"] ||= []
  people_groups[row["people_group_id"].to_i]["SubGroups"].push(clean(row))
end

people_groups.each do |x|
  if x
    pg = PeopleGroup.create(x)
  end
end

country_to_id = {}
Country.each { |c| country_to_id[c.country_id] = c }
pg_to_id = {}
PeopleGroup.each { |c| pg_to_id[c.people_group_id] = c }

Community.delete_all

puts("Reading main people group table")
CSV.foreach("original-data/tblLnkPEOtoGEO.csv", :headers => true, :converters => :all) do |row|
  people_geographic[row["people_group_id"].to_s+":"+row["country_id"]] = row.to_hash.compact # Don't clean yet
end

puts("Reading religion data")
CSV.foreach("original-data/tblLnkPEOtoGEOReligions.csv", :headers => true, :converters => :all) do |row|
  if not people_geographic.key?(row["people_group_id"].to_s+":"+row["country_id"])
    puts "Error: No entry in tblLnkPEOtoGEO for #{row["people_group_id"].to_s+":"+row["country_id"]}"
    people_geographic[row["people_group_id"].to_s+":"+row["country_id"]] = {}
  end
  people_geographic[row["people_group_id"].to_s+":"+row["country_id"]]["religions"] ||=[]
  if row["PercentAdherents"] && row["PercentAdherents"] > 0
    people_geographic[row["people_group_id"].to_s+":"+row["country_id"]]["religions"].push(clean(row))
  end
end

puts("Reading language data")
CSV.foreach("original-data/tbllnkLNGtoPEOGEO.csv", :headers => true, :converters => :all) do |row|
  if not people_geographic.key?(row["people_group_id"].to_s+":"+row["country_id"])
    puts "Error: No entry in tblLnkPEOtoGEO for #{row["people_group_id"].to_s+":"+row["country_id"]}"
    people_geographic[row["people_group_id"].to_s+":"+row["country_id"]] = {}
  end
  people_geographic[row["people_group_id"].to_s+":"+row["country_id"]]["languages"] ||=[]
  lang = languages[row["language_id"]]
  if not lang
    puts "No language found for code "+row["language_id"]
  end
  languageprofile = {
    language: lang,
    code: row["language_id"],
    rank: (row["LanguageRank"] == "P" ? "Primary" : "Secondary")
  }
  if row["dialect_id"].to_i != 0
    languageprofile[:dialect] = dialects[row["dialect_id"].to_i]
  end
  people_geographic[row["people_group_id"].to_s+":"+row["country_id"]]["languages"].push(languageprofile)
end

puts("Tidying")
people_geographic.each do |k,v|
  if v.key?("religions") and v.key?("PopulationRounded")
    rel2 = {}
    v["religions"].each do |religion|
      relname = religion["religion"]
      if not rel2.key?(relname) or rel2[relname]["Version"] > religion["Version"]
        rel2[relname] = religion
      end
    end
    rel2.each do |k,v|
      rel2[k] = v.except("Version", "PrimaryReligionFlag")
    end
    v["religions"] = rel2.values.sort_by{|x| x["PercentAdherents"].to_f }.reverse
    v["EvangelicalPercentage"] = (v["religions"].select{|x| x.key?("PercentEvangelical")}.max_by {|x| x["Version"] }||{})["PercentEvangelical"] || 0
    v["EvangelicalPopulation"] = (v["EvangelicalPercentage"] / 100 * v["LocalPopl"]).to_i
  end
  v["EvangelicalPopulation"] ||= 0
  v["country"] = country_to_id[v.delete("country_id")]
  v["people_group"] = pg_to_id[v.delete("people_group_id")]
  v["population"] = v["LocalPopl"] || v["PopulationRounded"] || 0

  if v["country"] and v["people_group"]
    new_com = Community.create(clean(v))
    new_com["is_diaspora"] = v["people_group"] ? (new_com.people_group.home_country != new_com.country) : "N"
  end
  if new_com.respond_to? :Longitude and new_com.respond_to? :Latitude
  new_com.location = [new_com.Longitude, new_com.Latitude]
  new_com.save!
end

Community.create_indexes