# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/utils"

module Dependabot
  class DependabotError < StandardError
    extend T::Sig

    BASIC_AUTH_REGEX = %r{://(?<auth>[^:@]*:[^@%\s/]+(@|%40))}
    # Remove any path segment from fury.io sources
    FURY_IO_PATH_REGEX = %r{fury\.io/(?<path>.+)}

    sig { params(message: T.any(T.nilable(String), MatchData)).void }
    def initialize(message = nil)
      super(sanitize_message(message))
    end

    private

    sig { params(message: T.any(T.nilable(String), MatchData)).returns(T.any(T.nilable(String), MatchData)) }
    def sanitize_message(message)
      return message unless message.is_a?(String)

      path_regex =
        Regexp.escape(Utils::BUMP_TMP_DIR_PATH) + "\\/" +
        Regexp.escape(Utils::BUMP_TMP_FILE_PREFIX) + "[a-zA-Z0-9-]*"

      message = message.gsub(/#{path_regex}/, "dependabot_tmp_dir").strip
      filter_sensitive_data(message)
    end

    sig { params(message: String).returns(String) }
    def filter_sensitive_data(message)
      replace_capture_groups(message, BASIC_AUTH_REGEX, "")
    end

    sig { params(source: String).returns(String) }
    def sanitize_source(source)
      source = filter_sensitive_data(source)
      replace_capture_groups(source, FURY_IO_PATH_REGEX, "<redacted>")
    end

    sig do
      params(
        string: String,
        regex: Regexp,
        replacement: String
      ).returns(String)
    end
    def replace_capture_groups(string, regex, replacement)
      string.scan(regex).flatten.compact.reduce(string) do |original_msg, match|
        original_msg.gsub(match, replacement)
      end
    end
  end

  class OutOfDisk < DependabotError; end

  class OutOfMemory < DependabotError; end

  class NotImplemented < DependabotError; end

  #####################
  # Repo level errors #
  #####################

  class DirectoryNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :directory_name

    sig { params(directory_name: String, msg: T.nilable(String)).void }
    def initialize(directory_name, msg = nil)
      @directory_name = directory_name
      super(msg)
    end
  end

  class BranchNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :branch_name

    sig { params(branch_name: String, msg: T.nilable(String)).void }
    def initialize(branch_name, msg = nil)
      @branch_name = branch_name
      super(msg)
    end
  end

  class RepoNotFound < DependabotError
    extend T::Sig

    sig { returns(T.any(Dependabot::Source, String)) }
    attr_reader :source

    sig { params(source: T.any(Dependabot::Source, String), msg: T.nilable(String)).void }
    def initialize(source, msg = nil)
      @source = source
      super(msg)
    end
  end

  #####################
  # File level errors #
  #####################

  class ToolVersionNotSupported < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :tool_name

    sig { returns(String) }
    attr_reader :detected_version

    sig { returns(String) }
    attr_reader :supported_versions

    sig do
      params(
        tool_name: String,
        detected_version: String,
        supported_versions: String
      ).void
    end
    def initialize(tool_name, detected_version, supported_versions)
      @tool_name = tool_name
      @detected_version = detected_version
      @supported_versions = supported_versions

      msg = "Dependabot detected the following #{tool_name} requirement for your project: '#{detected_version}'." \
            "\n\nCurrently, the following #{tool_name} versions are supported in Dependabot: #{supported_versions}."
      super(msg)
    end
  end

  class DependencyFileNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg || "#{file_path} not found")
    end

    sig { returns(String) }
    def file_name
      T.must(file_path.split("/").last)
    end

    sig { returns(String) }
    def directory
      # Directory should always start with a `/`
      T.must(file_path.split("/")[0..-2]).join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotParseable < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :file_path

    sig { params(file_path: String, msg: T.nilable(String)).void }
    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg || "#{file_path} not parseable")
    end

    sig { returns(String) }
    def file_name
      T.must(file_path.split("/").last)
    end

    sig { returns(String) }
    def directory
      # Directory should always start with a `/`
      T.must(file_path.split("/")[0..-2]).join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotEvaluatable < DependabotError; end

  class DependencyFileNotResolvable < DependabotError; end

  #######################
  # Config file errors  #
  #######################

  class ConfigFileFileNotFound < DependabotError; end

  #######################
  # Source level errors #
  #######################

  class PrivateSourceAuthenticationFailure < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    def initialize(source)
      @source = T.let(sanitize_source(source), String)
      msg = "The following source could not be reached as it requires " \
            "authentication (and any provided details were invalid or lacked " \
            "the required permissions): #{@source}"
      super(msg)
    end
  end

  class PrivateSourceTimedOut < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: String).void }
    def initialize(source)
      @source = T.let(sanitize_source(source), String)
      super("The following source timed out: #{@source}")
    end
  end

  class PrivateSourceCertificateFailure < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: String).void }
    def initialize(source)
      @source = T.let(sanitize_source(source), String)
      super("Could not verify the SSL certificate for #{@source}")
    end
  end

  class MissingEnvironmentVariable < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :environment_variable

    sig { params(environment_variable: String).void }
    def initialize(environment_variable)
      @environment_variable = environment_variable
      super("Missing environment variable #{@environment_variable}")
    end
  end

  # Useful for JS file updaters, where the registry API sometimes returns
  # different results to the actual update process
  class InconsistentRegistryResponse < DependabotError; end

  ###########################
  # Dependency level errors #
  ###########################

  class GitDependenciesNotReachable < DependabotError
    extend T::Sig

    sig { returns(T::Array[String]) }
    attr_reader :dependency_urls

    sig { params(dependency_urls: T.any(String, T::Array[String])).void }
    def initialize(*dependency_urls)
      @dependency_urls =
        T.let(dependency_urls.flatten.map { |uri| filter_sensitive_data(uri) }, T::Array[String])

      msg = "The following git URLs could not be retrieved: " \
            "#{@dependency_urls.join(', ')}"
      super(msg)
    end
  end

  class GitDependencyReferenceNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :dependency

    sig { params(dependency: String).void }
    def initialize(dependency)
      @dependency = dependency

      msg = "The branch or reference specified for #{@dependency} could not " \
            "be retrieved"
      super(msg)
    end
  end

  class PathDependenciesNotReachable < DependabotError
    extend T::Sig

    sig { returns(T::Array[String]) }
    attr_reader :dependencies

    sig { params(dependencies: T.any(String, T::Array[String])).void }
    def initialize(*dependencies)
      @dependencies = T.let(dependencies.flatten, T::Array[String])
      msg = "The following path based dependencies could not be retrieved: " \
            "#{@dependencies.join(', ')}"
      super(msg)
    end
  end

  class GoModulePathMismatch < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :go_mod

    sig { returns(String) }
    attr_reader :declared_path

    sig { returns(String) }
    attr_reader :discovered_path

    sig { params(go_mod: String, declared_path: String, discovered_path: String).void }
    def initialize(go_mod, declared_path, discovered_path)
      @go_mod = go_mod
      @declared_path = declared_path
      @discovered_path = discovered_path

      msg = "The module path '#{@declared_path}' found in #{@go_mod} doesn't " \
            "match the actual path '#{@discovered_path}' in the dependency's " \
            "go.mod"
      super(msg)
    end
  end

  # Raised by UpdateChecker if all candidate updates are ignored
  class AllVersionsIgnored < DependabotError; end

  # Raised by FileParser if processing may execute external code in the update context
  class UnexpectedExternalCode < DependabotError; end
end
