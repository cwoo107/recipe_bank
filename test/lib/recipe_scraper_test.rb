require "test_helper"

class RecipeScraperTest < ActiveSupport::TestCase
  def scrape_fixture(name)
    scraper = RecipeScraper.new("https://example.com/r")
    scraper.instance_variable_set(:@doc, Nokogiri::HTML(file_fixture(name).read))
    scraper.scrape_document
  end

  test "finds a Recipe nested in an @graph inside an array, with a list for its @type" do
    data = scrape_fixture("recipe_jsonld_graph.html")

    assert_equal "Mom’s Apple Pie", data[:title]
    assert_equal 8, data[:servings]
    assert_equal ["2 ½ cups flour", "6 apples"], data[:ingredients]
  end

  test "decodes entities and drops tags in JSON-LD text" do
    data = scrape_fixture("recipe_jsonld_graph.html")

    assert_equal "Flaky crust & tart apples.", data[:description]
    assert_equal ["Crust: Mix the flour.", "Chill it.", "Bake at 375°F."], data[:steps]
  end

  test "reads a page without recipe data from its HTML, using the meta description" do
    data = scrape_fixture("recipe_plain_html.html")

    assert_equal "Tomato Soup", data[:title]
    assert_equal "A simple weeknight soup.", data[:description]
    assert_equal 4, data[:servings]
    assert_equal ["1 can tomatoes", "Salt & pepper"], data[:ingredients]
    assert_equal ["Simmer the tomatoes.", "Season."], data[:steps]
  end

  def scrape_with_fetch_error(error)
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch) { raise error }
    SafeUrlFetcher.stub(:new, fetcher) do
      assert_raises(SafeUrlFetcher::Error) { RecipeScraper.new("https://example.com/r").scrape }
    end
  end

  test "a site that blocks the fetch points to importing from a file" do
    blocked = SafeUrlFetcher::Error.new("The site responded with an error (403).", reason: :http_status, status: 403)
    error = scrape_with_fetch_error(blocked)

    assert_equal RecipeScraper::BLOCKED_MESSAGE, error.message
    assert_equal 403, error.status
  end

  test "other fetch errors keep their own message" do
    missing = SafeUrlFetcher::Error.new("The site responded with an error (404).", reason: :http_status, status: 404)

    assert_equal missing.message, scrape_with_fetch_error(missing).message
  end

  test "a page with no recipe comes back empty rather than with a placeholder title" do
    data = scrape_fixture("not_a_recipe.html")

    assert_nil data[:title]
    assert_empty data[:ingredients]
    assert_empty data[:steps]
  end
end
