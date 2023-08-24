require "http/headers"

# HTTP modifies the header names, replacing underscores with dashes and
# capitalizing each word, this causes issues with api's that expect
# certain headers.
HTTP::Headers.class_eval do
  def normalize_header(name)
    name
  end
end
