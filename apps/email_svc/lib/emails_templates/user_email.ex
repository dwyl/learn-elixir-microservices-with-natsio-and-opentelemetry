defmodule Emails.Templates do
  import Swoosh.Email

  @moduledoc """
  Module for constructing user-related emails.
  Provides functions to create welcome and notification emails.
  """

  @from {"Email Service", "noreply@example.com"}

  def welcome_email(to_email, user_name) do
    %Swoosh.Email{} =
      new()
      |> to(to_email)
      |> from(@from)
      |> subject("Welcome to our service!")
      |> html_body("<h1>Welcome #{user_name}!</h1><p>Thank you for joining us.</p>")
      |> text_body("Welcome #{user_name}! Thank you for joining us.")
  end

  def notification_email(to_email, user_name, subject, body) do
    %Swoosh.Email{} =
      new()
      |> to(to_email)
      |> from(@from)
      |> subject(subject)
      |> html_body("<h1>Hello #{user_name}</h1><p>#{body}</p>")
      |> text_body("Hello #{user_name}\n\n#{body}")
  end
end
