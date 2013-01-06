#!/usr/bin/env ruby
#
# @author     Jie Fan
#             i@jiefan.me
# @create     05/01/2013 21:54:24 EST
#

require "faraday"
require "uri"
require "xmlsimple"
require "json"

APP_INFO = ["appID", "appKey"]
API_ADDR = "https://api.octranspo1.com/v1.1/"
API_NAME = "GetNextTripsForStop"
STOP_AND_ROUTE_INFO = { "0867" => [ "93" ] }
STOP_LOCATION = [45.338196, -75.911385]
TRIP_RES = "GetNextTripsForStopResponse" 
TRIP_REL = "GetNextTripsForStopResult"
LOCATION_API = "http://www.mapquestapi.com/"
LOCATION_API_NAME = "directions/v1/routematrix?key=MapRequestKey"

class Object
  def try(fun, *args)
    return nil if self.nil?
    self.__send__ fun, *args
  end
end

class Notifier
  def self.notify(title, body)
    `notify-send -t 5000 "#{title}" "#{body}"`
  end
end

class DataFetcher
  def initialize
    @conn = Faraday.new(API_ADDR) do |faraday|
              faraday.request :url_encoded
              faraday.adapter Faraday.default_adapter
            end
    @loc_conn = Faraday.new(LOCATION_API) do |faraday|
                  faraday.request :url_encoded
                  faraday.adapter Faraday.default_adapter
                end
  end
  
  def run
    fetch_data
  end

  private
  def parse_xml(xml)
    XmlSimple.
      xml_in(xml)["Body"].
      first[TRIP_RES].
      first[TRIP_REL].
      first["Route"].
      first["RouteDirection"].
      first["Trips"].
      first["Trip"].
      first
  end

  def parse_json(json)
    JSON.parse(json)["distance"].try(:last).try(:to_f)
  end

  def fetch_location_info(loc1, loc2)
    @loc_conn.post do |req|
      req.url LOCATION_API_NAME
      req.headers['Content-Type'] = 'application/json'
      req.body = "{ 'locations': ['#{loc1.join(',')}', '#{loc2.join(',')}'] }"
    end.body
  end

  def fetch_raw_data(stop, route)
    app_id, app_key = APP_INFO
    @conn.post(
      API_NAME,
      {
        :appID   => app_id,
        :apiKey  => app_key,
        :routeNo => route,
        :stopNo  => stop
      }
    ).body
  end

  def fetch_data
    STOP_AND_ROUTE_INFO.each_pair do |stop, routes|
      routes.each do |route|
        raw_data = fetch_raw_data(stop, route)
        trip_info = parse_xml(raw_data)

        latitude = trip_info["Latitude"].first
        longtitude = trip_info["Longitude"].first
        speed = trip_info["GPSSpeed"].first
        destination = trip_info["TripDestination"].first

        unless latitude.empty? or longtitude.empty? or speed.empty?
          location = [latitude, longtitude].map(&:to_f)
          json_info = fetch_location_info(location, STOP_LOCATION)
          distance = parse_json(json_info)

          unless distance.nil?
            t = distance / speed.to_f * 60
            Notifier.notify("Bus coming!", "Route #{route} going to #{destination} will arrive at stop #{stop} in #{t.round(2)}")
          end
        end
      end
    end 
  end
end

if __FILE__ == $0
  DataFetcher.new.run  
end
