defmodule ExOAPI.GeneratorTest do
  use ExUnit.Case
  doctest ExOAPI.Generator

  test "greets the world" do
    assert ExOAPI.Generator.hello() == :world
  end
end
