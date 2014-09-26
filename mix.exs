defmodule Axe.Mixfile do
  use Mix.Project

  def project do
    [app: :axe,
     version: "0.0.2",
     elixir: "~> 1.0.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :hackney],
     mod: {Axe, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      { :"exactor" , "~> 0.7.0"                } ,
      { :"hackney" , "~> 0.13.1"               } ,
      { :"jazz"    , "~> 0.2.1"  , only: :test } ,
      { :httparrot , "~> 0.3.2"  , only: :test }
    ]
  end
end
