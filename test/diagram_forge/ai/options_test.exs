defmodule DiagramForge.AI.OptionsTest do
  use ExUnit.Case, async: true

  alias DiagramForge.AI.Options

  describe "new/1" do
    test "creates valid options with user_id and operation" do
      assert {:ok, opts} = Options.new(user_id: "user-123", operation: "diagram_generation")

      assert opts.user_id == "user-123"
      assert opts.operation == "diagram_generation"
      assert opts.track_usage == true
    end

    test "creates valid options with track_usage disabled and nil user_id" do
      assert {:ok, opts} = Options.new(operation: "diagram_generation", track_usage: false)

      assert opts.user_id == nil
      assert opts.operation == "diagram_generation"
      assert opts.track_usage == false
    end

    test "returns error when operation is missing" do
      assert {:error, "operation is required"} = Options.new(user_id: "user-123")
    end

    test "returns error when operation is invalid" do
      assert {:error, message} = Options.new(user_id: "user-123", operation: "invalid_op")
      assert message =~ "invalid operation"
      assert message =~ "diagram_generation"
      assert message =~ "syntax_fix"
    end

    test "returns error when user_id is missing and track_usage is true" do
      assert {:error, "user_id is required when track_usage is enabled"} =
               Options.new(operation: "diagram_generation")
    end

    test "returns error when user_id is nil and track_usage is true" do
      assert {:error, "user_id is required when track_usage is enabled"} =
               Options.new(user_id: nil, operation: "diagram_generation")
    end

    test "accepts syntax_fix operation" do
      assert {:ok, opts} = Options.new(user_id: "user-123", operation: "syntax_fix")
      assert opts.operation == "syntax_fix"
    end

    test "preserves ai_client option" do
      assert {:ok, opts} =
               Options.new(
                 user_id: "user-123",
                 operation: "diagram_generation",
                 ai_client: SomeModule
               )

      assert opts.ai_client == SomeModule
    end
  end

  describe "new!/1" do
    test "returns options on success" do
      opts = Options.new!(user_id: "user-123", operation: "diagram_generation")
      assert opts.user_id == "user-123"
    end

    test "raises ArgumentError on validation failure" do
      assert_raise ArgumentError, "user_id is required when track_usage is enabled", fn ->
        Options.new!(operation: "diagram_generation")
      end
    end
  end

  describe "to_keyword_list/1" do
    test "converts options to keyword list" do
      {:ok, opts} = Options.new(user_id: "user-123", operation: "diagram_generation")

      keyword_list = Options.to_keyword_list(opts)

      assert Keyword.get(keyword_list, :user_id) == "user-123"
      assert Keyword.get(keyword_list, :operation) == "diagram_generation"
      assert Keyword.get(keyword_list, :track_usage) == true
    end

    test "includes ai_client in keyword list when present" do
      {:ok, opts} =
        Options.new(
          user_id: "user-123",
          operation: "diagram_generation",
          ai_client: SomeModule
        )

      keyword_list = Options.to_keyword_list(opts)

      assert Keyword.get(keyword_list, :ai_client) == SomeModule
    end

    test "excludes ai_client from keyword list when nil" do
      {:ok, opts} = Options.new(user_id: "user-123", operation: "diagram_generation")

      keyword_list = Options.to_keyword_list(opts)

      refute Keyword.has_key?(keyword_list, :ai_client)
    end
  end
end
