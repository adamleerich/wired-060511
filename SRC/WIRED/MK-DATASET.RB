#!/usr/local/bin/ruby -w

# == Synopsis
#
# Generates the WIRED dataset from WIRED Difference Files in XML format.
#
# == Usage
#
# Usage: ./mk-dataset.rb parameters file ...
# 
#         --action|-x A|O (default = A) 
#                 Action to perform relative to output - add/overwrite
# 
#         --debug|-d  
#                 Generate extra columns in output file for debugging purposes
# 
#         --help|-h  
#                 Displays this message
# 
#         --no-headers|-n  
#                 Don't put column headers at top of output file
# 
#         --output|-o file 
#                 ASCII Windows Registry Dataset file, stdout is default
# 
#         --verbose|-v  
#                 Verbose mode
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
# protection and is in the public domain. Reg-Diff is an experimental
# system. NIST assumes no responsibility whatsoever for its use by
# other parties, and makes no guarantees, expressed or implied, about
# its quality, reliability, or any other characteristic. We would
# appreciate acknowledgement if the software is used. This software
# can be redistributed and/or modified freely provided that any
# derivative works bear some notice that they are derived from it,
# and any modified versions bear some notice that they have been
# modified.

$; = "\t"

require 'cmdln'
require 'wired-dataset'

include Wired::Dataset

# define command-line parameters
action =
  CmdLn::Parameter.new(false, '--action', '-x',
    CmdLn::Parameter::REQUIRED_ARGUMENT,
    "A|O (default = A)", "Action to perform relative to output - add/overwrite",
    Proc.new {|opt, arg, parms|
      my_arg = arg.upcase
      if my_arg =~ /^(A|O)$/
        opt.value = my_arg
      else
        raise sprintf("Invalid parameter value: %s", my_arg)
      end
    })

output = CmdLn::OutputFileNameParameter.new(false, '--output', '-o', 'ASCII Windows Registry Dataset file, stdout is default')

debug =
  CmdLn::Parameter.new(false, '--debug', '-d',
    CmdLn::Parameter::NO_ARGUMENT,
    "", 'Generate extra columns in output file for debugging purposes',
    Proc.new {|opt, arg, parms|
      Wired::Dataset::set_debug_mode(true)
    })

no_headers = CmdLn::FlagParameter.new('--no-headers', '-n', 'Don\'t put column headers at top of output file')

verbose =
  CmdLn::Parameter.new(false, '--verbose', '-v',
    CmdLn::Parameter::NO_ARGUMENT,
    "", "Verbose mode")
    
help = CmdLn::HelpParameter.new

cmd_ln = CmdLn::Parameters.new([action, output, debug, no_headers, verbose, help], true)
cmd_ln.process_parameters

begin
  # provide the necessary defaults
  if action.value.nil?
    action.value = 'A'
  end

  fp_output =
    if output.value.nil?
      $stdout
    elsif action.value == 'A'
      File.new(output.value, 'a')
    else
      File.new(output.value, 'w')
    end

  if not (action.value == 'A' and no_headers)
    DatasetRecord.write_header(fp_output)
  end

  ARGV.each do |fname|
    begin
      $stderr.printf("Reading %s ...\n", fname) if verbose.value
      fp_input  = File.new(fname)
      input_doc = Wired::Dataset::open_document(fp_input)
      baseline  = Baseline.new(fname, input_doc)
      delta     = Delta.new(fname, input_doc)
      diffnode  = DiffNode.new(fname, input_doc)

      $stderr.printf("%s: processing entries added\n", fname) if verbose.value
      added = AddedEntries.new(fp_input, input_doc, baseline, delta, diffnode)

      $stderr.printf("%s: processing entries deleted\n", fname) if verbose.value
      deleted = DeletedEntries.new(fp_input, input_doc, baseline, delta, diffnode)

      $stderr.printf("%s: processing entries modified\n", fname) if verbose.value
      modified = ModifiedEntries.new(fp_input, input_doc, baseline, delta, diffnode)
      
      begin
        added.write(fp_output)
        deleted.write(fp_output)
        modified.write(fp_output)
      rescue Exception => e
        # if we get here, something bad happened while we tried to write to the output file
        # and it is most likely corrupted
        $stderr.printf("Fatal Error: IO error while writing output for %s, processing aborted: %s\n", fname, e)
        exit(-1)
      end
    rescue SystemExit => e
      # don't want any further exception messages if we've already called exit()
    rescue Exception => e
      msg = "Warning: Ignoring file %s: %s\n"
      detail = e
      # if the file is just empty, I don't want to give a confusing message
      if File.exist?(fname) and File.file?(fname) and File.readable?(fname) and !File.size?(fname)
        detail = "Empty file"
      end
      $stderr.printf(msg, fname, detail)
      next
    end
  end
rescue Exception => e
  $stderr.printf("%s\n", e)
ensure
  fp_output.close() if !output.value.nil?
end

