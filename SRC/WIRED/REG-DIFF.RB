#!/usr/local/bin/ruby -w
 
# == Synopsis
#
# Generates an XML difference document of two Windows Registry ASCII
# patch files. Developed for use on Mac OS X as part of the NSRL
# Windows Registry project and should run without modification on
# similar systems. Requires uname which will be a problem on Windows
# systems.
#
# == Usage
#
# Usage: ./reg-diff.rb parameters
# 
#         --action|-x I/D/E/O 
#                 Install, Deinstall, Execute, Other
# 
#         --appname|-a "app name" 
#                 Note use of ""
# 
#         --baseline|-b file 
#                 Baseline registry file in ASCII format (UTF-16LE if --conv is used)
# 
#         --delta|-d file 
#                 Registry file w/changes in ASCII format (UTF-16LE if --conv is used)
# 
#         --conv|-c  
#                 Use libiconv to convert input files from UTF-16LE to ASCII
# 
#         --help|-h  
#                 Displays this message
# 
#         --nsrl|-n int 
#                 NSRL Application ID - if application is part of the NSRL
# 
#         --output|-o file 
#                 Output file, stdout is default
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

require 'cmdln'
require 'etc'
require 'iconv'
require 'rexml/document'
require 'sha1'
require 'tempfile'
require 'wired-diff'

include Wired::Diff

# Define the expected command-line parameters and then process the ones supplied at the command-line
baseline = CmdLn::InputFileNameParameter.new(true, '--baseline', '-b', 'Baseline registry file in ASCII format (UTF-16LE if --conv is used)')

delta = CmdLn::InputFileNameParameter.new(true, '--delta', '-d', 'Registry file w/changes in ASCII format (UTF-16LE if --conv is used)')

conv = CmdLn::FlagParameter.new('--conv', '-c', 'Use libiconv to convert input files from UTF-16LE to ASCII')

app_name =
  CmdLn::Parameter.new(true, '--appname','-a',
    CmdLn::Parameter::REQUIRED_ARGUMENT, 
    "\"app name\"","Note use of \"\"")

nsrl =
  CmdLn::Parameter.new(false, '--nsrl','-n',
  CmdLn::Parameter::REQUIRED_ARGUMENT, 
  "int","NSRL Application ID - if application is part of the NSRL")

action =
  CmdLn::Parameter.new(true, '--action', '-x',
  CmdLn::Parameter::REQUIRED_ARGUMENT, 
  "I/D/E/O","Install, Deinstall, Execute, Other",
  Proc.new {|opt, arg, parms|
    my_arg = arg.upcase
    if not my_arg =~ /^(I|D|E|O)$/
      raise CmdLn::ArgumentError.new(sprintf("Invalid parameter value: %s\n", my_arg))
    else
      opt.value = my_arg
    end
  })

output = CmdLn::OutputFileNameParameter.new(false, '--output', '-o', 'Output file, stdout is default')

help = CmdLn::HelpParameter.new

cmd_ln = CmdLn::Parameters.new([baseline, delta, conv, app_name, nsrl, action, output, help])
cmd_ln.process_parameters

FN_TEMP_B = 'reg-diff-b'
FN_TEMP_D = 'reg-diff-d'

begin
  # Collect metadata from the machine executing this script
  meta = WinRegDiffMetadata.new(baseline.value, delta.value, app_name.value, nsrl.value, action.value)

  if conv.value
    # Convert patch files from UTF-16LE to ASCII
    fn_temp_b = Tempfile.new(FN_TEMP_B)
    fn_temp_d = Tempfile.new(FN_TEMP_D)

    s_b = Wired::Diff::file_contents(baseline.value)
    s_d = Wired::Diff::file_contents(delta.value)

    tr = Iconv.new('ASCII//IGNORE', 'UTF-16LE')
    fn_temp_b << tr.iconv(s_b)
    fn_temp_b << tr.iconv(nil)
    fn_temp_b.close
    
    fn_temp_d << tr.iconv(s_d)
    fn_temp_d << tr.iconv(nil)
    fn_temp_d.close

    fp_baseline = fn_temp_b.open
    fp_delta = fn_temp_d.open
  else
    fp_baseline = File.new(baseline.value)
    fp_delta = File.new(delta.value)
  end
  
  fp_output =
    if output.value.nil?
      $stdout
    else
      File.new(output.value, 'w')
    end

  # Perform the differencing
  diff = WinRegDiff.new(fp_baseline, fp_delta)

  # Prepare and output an XML document containing the differences found
  doc = WinRegDiffDoc.new(meta, diff)
  doc.write(fp_output)

  # If there were bad values found in either patch files, dump them to stderr
  msg = "Warning: Ignoring badly formatted value found in %s: %s\n"

  diff.bad_baseline_values.each do |val|
    $stderr.printf(msg, baseline.value, val)
  end

  diff.bad_delta_values.each do |val|
    $stderr.printf(msg, delta.value, val)
  end
rescue Exception => e
  $stderr.printf("%s\n", e)
ensure
  fp_baseline.close if fp_baseline and not fp_baseline.closed?
  fp_delta.close    if fp_delta    and not fp_delta.closed?
  fp_output.close   if fp_output   and not output.value.nil?
end

