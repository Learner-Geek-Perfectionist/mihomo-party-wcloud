#!/usr/bin/env ruby
# frozen_string_literal: true

require "securerandom"
require "yaml"

SOURCE_DIR = File.expand_path(ARGV.fetch(0))
STAGE_DIR = File.expand_path(ARGV.fetch(1))
OVERRIDE_NAME = ARGV.fetch(2)
SOURCE_OVERRIDE_REGISTRY = File.join(SOURCE_DIR, "override.yaml")
SOURCE_PROFILE_PATH = File.join(SOURCE_DIR, "profile.yaml")
STAGE_OVERRIDE_REGISTRY = File.join(STAGE_DIR, "override.yaml")
STAGE_PROFILE_PATH = File.join(STAGE_DIR, "profile.yaml")

def load_yaml_mapping(path)
  return {} unless File.exist?(path)

  document = YAML.load_file(path)
  unless document.nil? || document.is_a?(Hash)
    raise "#{path} must contain a YAML mapping"
  end

  document || {}
end

def normalize_items(document, path)
  items = document["items"]
  return [] if items.nil?

  raise "#{path} items must be a YAML sequence" unless items.is_a?(Array)

  items.each do |item|
    raise "#{path} items must be YAML mappings" unless item.is_a?(Hash)
  end

  items
end

def write_yaml(path, document)
  tmp_path = File.join(File.dirname(path), ".#{File.basename(path)}.tmp.#{$PROCESS_ID}")
  File.write(tmp_path, YAML.dump(document))
  File.rename(tmp_path, path)
end

override_document = load_yaml_mapping(SOURCE_OVERRIDE_REGISTRY)
override_items = normalize_items(override_document, SOURCE_OVERRIDE_REGISTRY)
existing_override = override_items.find do |item|
  item["name"] == OVERRIDE_NAME && !item["id"].to_s.strip.empty?
end
override_id = existing_override && existing_override["id"].to_s.strip
override_id = SecureRandom.hex(5) if override_id.nil? || override_id.empty?

profile_status = "missing"
profile_document = nil
profile_items = nil
updated_profile_items = nil
if File.exist?(SOURCE_PROFILE_PATH)
  profile_document = load_yaml_mapping(SOURCE_PROFILE_PATH)
  profile_items = normalize_items(profile_document, SOURCE_PROFILE_PATH)
  updated_profile_items = profile_items.map do |item|
    next item unless item["name"] == "Wcloud"

    updated_item = item.dup
    updated_item["override"] = [override_id]
    updated_item["autoUpdate"] = true
    updated_item["interval"] = 360
    profile_status = "updated"
    updated_item
  end
end

override_output = override_document.dup
override_output["items"] = [
  {
    "id" => override_id,
    "name" => OVERRIDE_NAME,
    "type" => "local",
    "ext" => "yaml",
    "updated" => Time.now.to_i * 1000
  },
  *override_items.reject { |item| item["name"] == OVERRIDE_NAME }
]

write_yaml(STAGE_OVERRIDE_REGISTRY, override_output)

if profile_status == "updated"
  profile_output = profile_document.dup
  profile_output["items"] = updated_profile_items
  write_yaml(STAGE_PROFILE_PATH, profile_output)
end

puts override_id
puts profile_status
