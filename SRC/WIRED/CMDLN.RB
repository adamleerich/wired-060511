# == Synopsis
#
# Classes to handle command-line parameters in a more object-oriented
# fashion - at least when compared to GetoptLong. One neat feature
# is that the Parameter objects hold their own values.
#
# == Usage
#
# Example:
# 
#  require 'cmdln'
#  ...
#  output = CmdLn::Parameter.new(false, '--output', '-o',
#           CmdLn::Parameter::REQUIRED_ARGUMENT, "file","Output file, stdout is default")
#
#  help = CmdLn::Parameter.new(false, '--help', '-h',
#         CmdLn::Parameter::NO_ARGUMENT, "", "Displays this message",
#         Proc.new {|opt, arg, parms| $stderr.printf("%s\n", parms.usage) exit(-1) })
#  ...
#  cmd_ln = CmdLn::Parameters.new([output, help])
#  cmd_ln.process_parameters
#  ...
#  File.new(output.value, 'w')
#
# == Author
#
# Alden Dima
#
# == Copyright
#
# This software was developed at the National Institute of Standards
# and Technology by employees of the Federal Government in the course
# of their official duties. Pursuant to title 17 Section 105 of the
# United States Code this software is not subject to copyright
# protection and is in the public domain. This is an experimental
# system. NIST assumes no responsibility whatsoever for its use by
# other parties, and makes no guarantees, expressed or implied, about
# its quality, reliability, or any other characteristic. We would
# appreciate acknowledgement if the software is used. This software
# can be redistributed and/or modified freely provided that any
# derivative works bear some notice that they are derived from it,
# and any modified versions bear some notice that they have been
# modified.

module CmdLn
  require 'getoptlong'

  class UsageError < StandardError
  end

  class ArgumentError < ArgumentError
    attr_reader :msg
    def initialize(msg)
      @msg = msg
    end
    
    def to_s
      @msg
    end
  end

  class FileArgumentError < ArgumentError
    def initialize(file_name)
      super(sprintf("Can't open file: %s for I/O", file_name))
    end
  end

  # Describes a single command-line parameter that can be passed to a Ruby program, including the action 
  # to be performed (via a Proc object)
  class Parameter
    include Comparable
    attr_reader :is_required, :long_form, :short_form, :arg_flag, :arg_desc, :parm_desc
    attr_accessor :value

    # parameter does not have an associated value, eg. '--version'
    NO_ARGUMENT       = GetoptLong::NO_ARGUMENT

    # parameter may have an associated value
    OPTIONAL_ARGUMENT = GetoptLong::OPTIONAL_ARGUMENT

    # parameter must have an associated value, eg. '--file bob.txt'
    REQUIRED_ARGUMENT = GetoptLong::REQUIRED_ARGUMENT

    # default action for a parameter is simply to set its value to whatever arg is found for it on the command-line
    DEF_ACTION = Proc.new {|opt, arg, parms| opt.value = arg}

    # Create a new Parameter object. Some of the parameters are required by Ruby's GetoptLong which does much of the work
    # [_is_required_] A boolean that determines whether the parameter is required at the command-line
    # [_long_form_]   The parameter's long form, eg. --version
    # [_short_form_]  The parameter's short from eg. -v
    # [_arg_flag_]    One of constants defined in the Parameter class: NO_ARGUMENT, OPTIONAL_ARGUMENT, REQUIRED_ARGUMENT
    # [_arg_desc_]    A short string describing the parameter value's type, eg: file
    # [_parm_desc_]   A string describing the parameter's purpose, eg. "the target destination"
    # [_proc_]        The action to be performed when the parameter is encountered on the command-line. The default is
    #                 simply to assign the value given at the command-line to the Parameter object. Non-default behavior
    #                 can be specified via a Proc object similar to DEF_ACTION
    def initialize (is_required, long_form, short_form, arg_flag, arg_desc, parm_desc, proc=DEF_ACTION)
      @is_required = is_required
      @long_form   = long_form
      @short_form  = short_form
      @arg_flag    = arg_flag
      @arg_desc    = arg_desc
      @parm_desc   = parm_desc
      @value       = nil
      @proc        = proc
    end

    def <=> (other) #:nodoc:
      if self.is_required
        other.is_required ? self.long_form <=> other.long_form : -1
      else
        other.is_required ? 1 : self.long_form <=> other.long_form
      end
    end

    # Used to create a GetoptLong option array for a parameter
    def get #:nodoc:
      p = Array.new
      p.push(@long_form)
      p.push(@short_form) if @short_form != ""
      p.push(@arg_flag)
      return p
    end

    # Called by an instance of Parameters to perform the parameter's specified action when it is
    # encountered on the command-line
    # [_opt_]   the option string given at the command-line
    # [_arg_]   the option's value string
    # [_parms_] the Parameters object
    def action (opt, arg, parms)
      @proc.call(opt, arg, parms)
    end
  end

  # Convenient implementation of an optional command-line flag - if it appears on the
  # command line, then its value is true, otherwise it is nil.
  class FlagParameter < Parameter
    def initialize (long_form, short_form, parm_desc)
      super(false, long_form, short_form,
        CmdLn::Parameter::NO_ARGUMENT, "", parm_desc,
        Proc.new {|opt, arg, parms| opt.value = true})
      end
  end

  # Convenient implementation of "--help", just initialize and pass along
  # with the other Parameter objects to Parameters#new
  class HelpParameter < Parameter
    def initialize
      super(false, '--help', '-h',
        CmdLn::Parameter::NO_ARGUMENT, "",
        "Displays this message",
        Proc.new {|opt, arg, parms| raise CmdLn::UsageError })
    end
  end

  # Implementation of a parameter designating an input file. Tests to ensure than the file referred to
  # exists, is a normal file and is readable. Throws CmdLn::FileArgumentError if the test fails. This exception
  # is handled by CmdLn::Parameters#process_parameters
  class InputFileNameParameter < Parameter
    # Create a new InputFileNameParameter object
    # [_is_required_] Boolean signalling  whether this parameter is required at the command-line
    # [_long_form_]   The parameter's long form, eg. '--help'
    # [_short_form_]  The parameter's short form, eg. '-h'
    def initialize (is_required, long_form, short_form, parm_desc)
      super(is_required, long_form, short_form, CmdLn::Parameter::REQUIRED_ARGUMENT, 'file', parm_desc, 
        Proc.new {|opt, arg, parms|
          if File.exists?(arg) and File.file?(arg) and File.readable?(arg)
            opt.value = arg
          else
            raise CmdLn::FileArgumentError.new(arg)
          end
        })
    end
  end

  # Implementation of a parameter designating an output file. Tests to ensure than the file referred to
  # exists, is a normal file and is writable. Throws CmdLn::FileArgumentError if the test fails. This exception
  # is handled by CmdLn::Parameters#process_parameters
  class OutputFileNameParameter < Parameter
    # Create a new OutputFileNameParameter object
    # [_is_required_] Boolean signalling  whether this parameter is required at the command-line
    # [_long_form_]   The parameter's long form, eg. '--help'
    # [_short_form-]  The parameter's short form, eg. '-h'
    # [_is_required_] Boolean signalling  whether this parameter is required at the command-line
    # [_long_form_]   The parameter's long form, eg. '--help'
    # [_parm_desc_]   A String describing the parameter's intent
    def initialize (is_required, long_form, short_form, parm_desc)
      super(is_required, long_form, short_form, CmdLn::Parameter::REQUIRED_ARGUMENT, 'file', parm_desc, 
        Proc.new {|opt, arg, parms|
          if File.exists?(arg) and File.file?(arg)
            if File.writable?(arg)
              opt.value = arg
            else
              raise CmdLn::FileArgumentError.new(arg)
            end
          else
            opt.value = arg
          end
        })
    end
  end

  # Convenient implementation of "--verbose", just initialize and pass along
  # with the other Parameter objects to Parameters#new
  class VerboseParameter < Parameter
    def initialize
      super(false, '--verbose', '-v',
        CmdLn::Parameter::NO_ARGUMENT, "", "Verbose mode")
    end
  end

  # Describes the set of command-line parameters that can be passed to a Ruby program
  class Parameters
    include Enumerable
    # Create a new Parameters object
    # [_parms_]    is an Array of Parameter objects
    # [_has_argf_] is a boolean that indicates whether there are trailing file names on the command-line
    def initialize (parms, has_argf=false)
      @parms = parms
      @parm_names = Hash.new
      @parms.each do |parm|
        @parm_names[parm.long_form] = parm
      end
      @has_argf = has_argf
    end

    def each
      @parms.each do |parm|
        yield parm
      end
    end

    # Return script usage as a string
    def usage
      hint = "\nUsage: " + $0 + " parameters#{@has_argf ? ' file ...' : ''}\n\n"
      @parms.sort.each do |parm|
        hint += sprintf("\t%s|%s %s \n\t\t%s\n\n", parm.long_form, parm.short_form, parm.arg_desc, parm.parm_desc)
      end
      return hint
    end

    # Handle a command-line usage error by printing a usage message to standard error and exiting
    def usage_error
      $stderr.printf("%s\n", usage)
      exit(-1)
    end

    # Return the Parameter object associated with a parameter long form, eg. "--version" => #<CmdLn::Parameter:0x32d898 ... >
    def get_parm_named(long_form)
      return @parm_names[long_form]
    end

    # Return whether a given long form is associated with a Parameter object, eg. "--bogus" => false
    def is_parm?(long_form)
      return !@parm_names[long_form].nil?
    end

    # Process each command-line parameter in turn, performing its specified action
    def process_parameters
      # Build and eval code to get option list. Using this yucky approach
      # because GetoptLong.new expects its parameters given individually;
      # I can't just build an array and pass it along.
      opts = nil
      cmd = "opts = GetoptLong.new("
      @parms.each_index do |i|
        cmd += "@parms[#{i}].get,"
      end
      cmd.chop!
      cmd += ")"
      eval(cmd)

      # Process each option
      begin
        opts.each do |opt, arg|
          parm = get_parm_named(opt)
          parm.action(parm, arg, self)
        end
      rescue UsageError
        usage_error
      rescue Exception => e
        $stderr.printf("Error: %s", e)
        usage_error
      end

      # Look for missing required command-line parameters
      missing = false
      @parms.each do |parm|
        if parm.is_required and parm.value.nil?
          $stderr.printf("Error: %s is a required parameter\n", parm.long_form)
          missing = true
        end
      end
      usage_error if missing
    end
  end
end

