defmodule StockFetcherWeb.GlossaryTest do
  use ExUnit.Case, async: true

  alias StockFetcherWeb.Glossary

  doctest StockFetcherWeb.Glossary

  test "every term has an id, a word, a one-liner and an explanation; ids are unique" do
    terms = Glossary.terms()

    for t <- terms do
      assert t.id =~ ~r/^[a-z0-9-]+$/
      assert t.term != "" and t.short != "" and t.body != ""
      assert is_list(t.aliases) and is_list(t.related)
    end

    assert length(Enum.uniq_by(terms, & &1.id)) == length(terms)
    assert length(Enum.uniq_by(terms, &String.downcase(&1.term))) == length(terms)
  end

  test "related terms all exist and never point at themselves" do
    for t <- Glossary.terms(), rel <- t.related do
      assert Glossary.get(rel), "#{t.id} relates to missing #{rel}"
      refute rel == t.id
    end
  end

  test "covers the words the plan asked for" do
    words = MapSet.new(Glossary.terms(), & &1.term)

    for word <-
          ~w(Long Short Entry Exit Position Take-profit Stop-loss Stop Cover Risk Target R:R OCO) do
      assert word in words, "missing #{word}"
    end
  end

  test "terms come alphabetically" do
    names = Enum.map(Glossary.terms(), &String.downcase(&1.term))
    assert names == Enum.sort(names)
  end

  describe "split_marked/1" do
    test "plain text stays one string; markers become terms with their labels" do
      assert Glossary.split_marked("no terms here") == ["no terms here"]

      assert Glossary.split_marked("[[r-r|R:R]] 1:2 and [[oco|OCO]].") ==
               [{:term, "r-r", "R:R"}, " 1:2 and ", {:term, "oco", "OCO"}, "."]
    end

    test "an unknown term id raises, so a typo can't ship silently" do
      assert_raise ArgumentError, ~r/unknown glossary term "stop-los"/, fn ->
        Glossary.split_marked("a [[stop-los]] here")
      end
    end
  end
end
