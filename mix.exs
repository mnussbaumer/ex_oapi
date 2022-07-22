defmodule ExOAPI.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_oapi,
      version: "0.1.5",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/mnussbaumer/ex_oapi",
      homepage_url: "https://hexdocs.pm/ex_oapi/readme.html",
      docs: [
        main: "ExOAPI",
        extras: ["README.md"]
      ],
      description:
        "Elixir library for generating HTTP clients from OpenAPI V3 json specifications",
      package: [
        exclude_patterns: [~r/.*~$/, ~r/#.*#$/],
        licenses: ["MIT"],
        links: %{
          "github/readme" => "https://github.com/mnussbaumer/ex_oapi"
        }
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application,
    do: [
      extra_applications: [:logger]
    ]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps,
    do: [
      {:ecto, "~> 3.8"},
      {:typed_ecto_schema, "~> 0.3"},
      {:tesla, "~> 1.4"},
      {:jason, "~> 1.2"},
      {:plug, "~> 1.13"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
end
