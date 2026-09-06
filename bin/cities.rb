#!/usr/bin/env ruby
# frozen_string_literal: true

# Single source of truth for the city tables (65 keys = data/*.jsonl filenames).
# Each city carries only the fields known for it:
#   location — Yelp search location string (collect_city + refresh_yelp_fields)
#   name     — display name
#   currency — ISO currency code (collect_city)
#   center   — [lat, lon] city center (radius guard in collect_city, batch nearby
#              searches in backfill_websites)
# Curated cities (nyc, singapore, ...) are refresh-only: no center/currency.
CITIES = {
  'amsterdam' => { location: 'Amsterdam, Netherlands', name: 'Amsterdam', currency: 'EUR', center: [52.37, 4.90] },
  'atlanta' => { location: 'Atlanta, GA, USA', name: 'Atlanta', currency: 'USD', center: [33.75, -84.39] },
  'auckland' => { location: 'Auckland, New Zealand', name: 'Auckland', currency: 'NZD', center: [-36.85, 174.76] },
  'austin' => { location: 'Austin, TX, USA', name: 'Austin', currency: 'USD', center: [30.27, -97.74] },
  'australia' => { location: 'Sydney, Australia' },
  'bangkok' => { location: 'Bangkok, Thailand' },
  'barcelona' => { location: 'Barcelona, Spain', name: 'Barcelona', currency: 'EUR', center: [41.39, 2.17] },
  'berlin' => { location: 'Berlin, Germany', name: 'Berlin', currency: 'EUR', center: [52.52, 13.40] },
  'boston' => { location: 'Boston, MA, USA', name: 'Boston', currency: 'USD', center: [42.36, -71.06] },
  'brisbane' => { location: 'Brisbane, QLD, Australia', name: 'Brisbane', currency: 'AUD', center: [-27.47, 153.03] },
  'brussels' => { location: 'Brussels, Belgium', name: 'Brussels', currency: 'EUR', center: [50.85, 4.35] },
  'buenos-aires' => { location: 'Buenos Aires, Argentina' },
  'chicago' => { location: 'Chicago, IL, USA', name: 'Chicago', currency: 'USD', center: [41.88, -87.63] },
  'copenhagen' => { location: 'Copenhagen, Denmark', name: 'Copenhagen', currency: 'DKK', center: [55.68, 12.57] },
  'dallas' => { location: 'Dallas, TX, USA', name: 'Dallas', currency: 'USD', center: [32.78, -96.80] },
  'denver' => { location: 'Denver, CO, USA', name: 'Denver', currency: 'USD', center: [39.74, -104.99] },
  'dubai' => { location: 'Dubai, UAE' },
  'dublin' => { location: 'Dublin, Ireland', name: 'Dublin', currency: 'EUR', center: [53.35, -6.26] },
  'fukuoka' => { location: 'Fukuoka, Japan', name: 'Fukuoka', currency: 'JPY', center: [33.59, 130.40] },
  'hong-kong' => { location: 'Hong Kong' },
  'houston' => { location: 'Houston, TX, USA', name: 'Houston', currency: 'USD', center: [29.76, -95.37] },
  'kyoto' => { location: 'Kyoto, Japan', name: 'Kyoto', currency: 'JPY', center: [35.01, 135.77] },
  'las-vegas' => { location: 'Las Vegas, NV, USA', name: 'Las Vegas', currency: 'USD', center: [36.17, -115.14] },
  'lisbon' => { location: 'Lisbon, Portugal', name: 'Lisbon', currency: 'EUR', center: [38.72, -9.14] },
  'london' => { location: 'London, UK', name: 'London', currency: 'GBP', center: [51.51, -0.13] },
  'los-angeles' => { location: 'Los Angeles, CA, USA', name: 'Los Angeles', currency: 'USD', center: [34.05, -118.24] },
  'madrid' => { location: 'Madrid, Spain', name: 'Madrid', currency: 'EUR', center: [40.42, -3.70] },
  'manila' => { location: 'Manila, Philippines' },
  'melbourne' => { location: 'Melbourne, VIC, Australia', name: 'Melbourne', currency: 'AUD',
                   center: [-37.81, 144.96] },
  'mexico-city' => { location: 'Mexico City, Mexico' },
  'miami' => { location: 'Miami, FL, USA', name: 'Miami', currency: 'USD', center: [25.76, -80.19] },
  'milan' => { location: 'Milan, Italy', name: 'Milan', currency: 'EUR', center: [45.46, 9.19] },
  'minneapolis' => { location: 'Minneapolis, MN, USA', name: 'Minneapolis', currency: 'USD', center: [44.98, -93.27] },
  'montreal' => { location: 'Montreal, QC, Canada', name: 'Montreal', currency: 'CAD', center: [45.50, -73.57] },
  'munich' => { location: 'Munich, Germany', name: 'Munich', currency: 'EUR', center: [48.14, 11.58] },
  'nagoya' => { location: 'Nagoya, Japan', name: 'Nagoya', currency: 'JPY', center: [35.18, 136.91] },
  'nashville' => { location: 'Nashville, TN, USA', name: 'Nashville', currency: 'USD', center: [36.16, -86.78] },
  'nyc' => { location: 'New York, NY' },
  'osaka' => { location: 'Osaka, Japan', name: 'Osaka', currency: 'JPY', center: [34.69, 135.50] },
  'paris' => { location: 'Paris, France', name: 'Paris', currency: 'EUR', center: [48.86, 2.35] },
  'perth' => { location: 'Perth, WA, Australia', name: 'Perth', currency: 'AUD', center: [-31.95, 115.86] },
  'philadelphia' => { location: 'Philadelphia, PA, USA', name: 'Philadelphia', currency: 'USD',
                      center: [39.95, -75.16] },
  'phoenix' => { location: 'Phoenix, AZ, USA', name: 'Phoenix', currency: 'USD', center: [33.45, -112.07] },
  'portland' => { location: 'Portland, OR, USA', name: 'Portland', currency: 'USD', center: [45.52, -122.68] },
  'prague' => { location: 'Prague, Czech Republic', name: 'Prague', currency: 'CZK', center: [50.08, 14.44] },
  'rome' => { location: 'Rome, Italy', name: 'Rome', currency: 'EUR', center: [41.90, 12.50] },
  'san-antonio' => { location: 'San Antonio, TX, USA', name: 'San Antonio', currency: 'USD', center: [29.42, -98.49] },
  'san-diego' => { location: 'San Diego, CA, USA', name: 'San Diego', currency: 'USD', center: [32.72, -117.16] },
  'san-francisco' => { location: 'San Francisco, CA, USA', name: 'San Francisco', currency: 'USD',
                       center: [37.77, -122.42] },
  'san-jose' => { location: 'San Jose, CA, USA', name: 'San Jose', currency: 'USD', center: [37.34, -121.89] },
  'sao-paulo' => { location: 'São Paulo, Brazil' },
  'sapporo' => { location: 'Sapporo, Japan', name: 'Sapporo', currency: 'JPY', center: [43.06, 141.35] },
  'seattle' => { location: 'Seattle, WA, USA', name: 'Seattle', currency: 'USD', center: [47.61, -122.33] },
  'seoul' => { location: 'Seoul, South Korea', name: 'Seoul', currency: 'KRW', center: [37.57, 126.98] },
  'shanghai' => { location: 'Shanghai, China' },
  'singapore' => { location: 'Singapore' },
  'stockholm' => { location: 'Stockholm, Sweden', name: 'Stockholm', currency: 'SEK', center: [59.33, 18.07] },
  'sydney' => { location: 'Sydney, NSW, Australia', name: 'Sydney', currency: 'AUD', center: [-33.87, 151.21] },
  'taipei' => { location: 'Taipei, Taiwan' },
  'tokyo' => { location: 'Tokyo, Japan', name: 'Tokyo', currency: 'JPY', center: [35.68, 139.69] },
  'toronto' => { location: 'Toronto, ON, Canada', name: 'Toronto', currency: 'CAD', center: [43.65, -79.38] },
  'vancouver' => { location: 'Vancouver, BC, Canada', name: 'Vancouver', currency: 'CAD', center: [49.28, -123.12] },
  'vienna' => { location: 'Vienna, Austria', name: 'Vienna', currency: 'EUR', center: [48.21, 16.37] },
  'washington-dc' => { location: 'Washington, DC, USA', name: 'Washington DC', currency: 'USD',
                       center: [38.91, -77.04] },
  'zurich' => { location: 'Zurich, Switzerland', name: 'Zurich', currency: 'CHF', center: [47.37, 8.54] }
}.freeze

# A city is collectable when it has both a center (radius-guard anchor) and a
# currency (entry metadata). Curated refresh-only cities (nyc, singapore, ...)
# omit one or both, so this one rule defines the collectable set.
def collectable?(city)
  !city[:center].nil? && !city[:currency].nil?
end

# Cities collect_city can collect, derived from collectable? — not hand-listed,
# so adding a center+currency to a curated city makes it collectable for free.
COLLECTABLE_CITIES = CITIES.select { |_, city| collectable?(city) }.freeze

def city_center(key)
  CITIES.dig(key, :center)
end

def city_location(key)
  CITIES.dig(key, :location)
end
