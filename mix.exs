defmodule HlCup.MixProject do
  use Mix.Project

  def project, do: [
      app: :hlcup,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() === :prod,
      deps: deps()
  ]

  def application, do: [
    mod: { HlCup, [] },
    extra_applications: [:logger],
  ]

  defp deps, do: [
    { :hlcup_nifs, path: "./c_src/", app: false }
  ]
end
