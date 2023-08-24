class NewImporter < Thor::Group
  include Thor::Actions
  source_root File.expand_path('templates', __dir__)
  argument :importer_name
  argument :methods, type: :array, banner: "api_key api_secret"

  def copy_pattern_file
    template "api.erb", "lib/crypto_importers/api/#{importer_name}_api.rb"
    template "importer.erb", "lib/crypto_importers/importers/#{importer_name}_importer.rb"
    template "spec.erb", "spec/importers/#{importer_name}_importer_spec.rb"
  end

  private

  def class_name
    importer_name.split('_').collect(&:capitalize).join
  end
end
