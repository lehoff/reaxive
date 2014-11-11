defmodule Reaxive.Mixfile do
  use Mix.Project

  def project do
    [ app: :reaxive,
      version: "0.0.2-dev",
      elixir: "~> 1.0.0",
      docs: [readme: true],
      test_coverage: [tool: Coverex.Task, log: :info, coveralls: true],
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: { Reaxive, [] },
      applications: [
        # httpoison is used for coverage testing only ...
        :httpoison, 
        # regular dependencies
        :kernel , :stdlib, :sasl, :logger]
    ]
  end

  defp deps do
    [      
      {:coverex, "~> 1.0.0", only: :test},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.6", only: :dev},
      {:dialyze, "~> 0.1.2", only: :dev},
      {:dbg, github: "fishcakez/dbg", only: :test}
   ]
  end
end
