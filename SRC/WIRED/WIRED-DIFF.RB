# == Synopsis
#
# Classes to enable the differencing of Windows Registry files in ASCII format and output
# the results in an XML-based format
#
# == Usage
#
# Example:
# 
#  require 'wired-diff'
#  include Wired::Diff
#  ...
#  meta = WinRegDiffMetadata.new(baseline.value, delta.value, app_name.value, nsrl.value, action.value)
#  ...
#  diff = WinRegDiff.new(fp_baseline, fp_delta)
#  ...
#  doc = WinRegDiffDoc.new(meta, diff)
#  doc.write(fp_output)
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
 
module Wired
  # Classes related to the differencing of Windows Registry patch files
  module Diff

    # Reads a file and outputs its SHA 1 value
    def Diff.sha1_file(file)
      return SHA1::new(File.new(file).read).to_s
    end

    # Returns the contents of a file as a string
    def Diff.file_contents(file)
      return File.new(file).read
    end

    # Represents Registry difference metadata. Collects diffnode system metadata automatically
    class WinRegDiffMetadata
      attr_reader :baseline, :baseline_sha, :delta, :delta_sha,
      :app_name, :nsrl, :action, :time

      # Create a new WinRegDiffMetadata object. Parameters are:
      # [_baseline_] the ASCII-ized Windows Registry patch file that will serve as the base case
      # [_delta_]    the ASCII-ized Windows Registry patch file that contains changes relative to the baseline
      # [_app_name_] the name of the application installed, deinstalled, or executed. If the delta is the result of a documented registry hack, then app_name is the name of that hack.
      # [_nsrl_]     the NSRL application ID if the application is part of the NSRL
      # [_action_]   the action performed to create the delta. One of _I_, _D_, _E_, or _O_ for Install, Deinstall, Execute, or Other
      def initialize(baseline, delta, app_name, nsrl, action)
        @baseline = baseline
        @baseline_sha = Diff.sha1_file(baseline)
        @delta = delta
        @delta_sha = Diff.sha1_file(delta)
        @time = Time.now.to_s
        @app_name = app_name
        @nsrl = nsrl
        @action = action
      end

      # Who's running this script?
      def user
        return Etc.getlogin
      end

      # Uses uname to determine diff node system architecture
      def arch
        return `uname -m`.chomp
      end

      # Uses uname to determine diff node system operating system
      def os
        return `uname -s`.chomp
      end

      # Uses uname to determine diff node system operating system version
      def osver
        return `uname -r`.chomp
      end

      # Uses uname to determine diff node system's name
      def sys
        return `uname -n`.chomp
      end
    end

    # Represents a single Windows Registry key
    class RegKey
      attr_reader :path
      def initialize(path)
        @path = path
      end
    end

    # Represents a single Windows Registry Value
    class RegValue
      attr_reader :path, :name, :data
      def initialize(path, name, data)
        @path = path
        @name = name
        @data = data
      end
    end

    # Represents the difference between two Windows Registry Patch
    # files. Sorts out the keys and values based on whether they were
    # added, deleted or modified (values only).
    class WinRegDiff
      attr_reader :key_add, :key_del, :val_add, :val_del, :val_mod, :bad_baseline_values, :bad_delta_values

      # Create a new WinRegDiff object
      # [_fp_b_] is the File object associated with the baseline Registry patch file
      # [_fp_d_] is the File object associated with the delta Registry patch file
      def initialize(fp_b, fp_d)
        keys_b, values_b, @bad_baseline_values = WinRegDiff.load_reg(fp_b)
        keys_d, values_d, @bad_delta_values = WinRegDiff.load_reg(fp_d)

        # sort out the keys based on whether they were added or deleted
        paths = (keys_b.keys + keys_d.keys).uniq
        @key_add = Array.new
        @key_del = Array.new
        paths.each do |path|
          key_b = keys_b[path]
          key_d = keys_d[path]
          if key_b.nil?
            @key_add.push(key_d)
          elsif key_d.nil?
            @key_del.push(key_b)
          end
        end

        # sort out values based on whether they were added, deleted, or modified
        paths = (values_b.keys + values_d.keys).uniq
        @val_add = Array.new
        @val_del = Array.new
        @val_mod = Array.new
        paths.each do |path|
          value_b = values_b[path]
          value_d = values_d[path]
          if value_b.nil?
            @val_add.push(value_d)
          elsif value_d.nil?
            @val_del.push(value_b)
          elsif value_b.data != value_d.data
            @val_mod.push(value_d)
          end
        end
      end

      # Load registry data from registry patch files
      private
      def WinRegDiff.load_reg(fp)
        reg_path = ''
        accum = nil
        reg_keys = Hash.new
        reg_values = Hash.new
        bad_values = Array.new

        if !fp.eof?
          fp.gets # dispose of header
        end

        fp.each do |line|
          line.strip!
          line.gsub!(/[[:cntrl:]]/, '?') # Gotta love control characters embedded in Registry entries
          if line =~ /^\[.*\]$/
            reg_path = line.slice(1 .. -2)
            reg_keys[reg_path] = RegKey.new(reg_path)
          elsif line =~ /^$/
            # ignore blank lines
          elsif line =~ /\\$/
            if accum.nil?
              accum = line.chop.lstrip
            else
              accum << line.chop.lstrip
            end
          else
            value_name_data = (accum ? accum : "") << line.lstrip
            value_name = value_data = nil
            parts = value_name_data.split('=')
            case parts.size
            when 2
              # the majority of registry values
              value_name, value_data = parts
            else
              # why do people do things like allow a field delimiter
              # to appear as a part of a field value?
              front = true
              if parts[0] == "@"
                front = false
                value_name = parts[0].clone
                parts.shift
              end

              parts.each do |part|
                if front
                  if value_name.nil?
                    value_name = part.clone
                  else
                     value_name << '=' << part.clone
                  end
                else
                  if value_data.nil?
                    value_data = part.clone
                  else
                    value_data << '=' << part
                  end
                end
                if front and part =~ /.*"$/
                  front = false
                end
              end
            end
            
            accum = nil if not accum.nil?

            # trying to thwart bad lines from RegEdit
            if value_name != "@" and value_name !~ /^".*"$/
              bad_values << "[#{reg_path}] #{value_name}=#{value_data}"
              next
            else
              value_name.gsub!(/^"|"$/) {}
            end

            # The existence checks are based on a fully qualified value name.
            lookup_key = reg_path.clone
            lookup_key <<  "\\" << value_name
            value = RegValue.new(reg_path, value_name, value_data)
            reg_values[lookup_key] = value
          end
        end
        return [reg_keys, reg_values, bad_values]
      end
    end

    # Represents the output.  All the work gets done during object
    # construction; you pretty much instantiate this object and then
    # write its contents to a file.
    class WinRegDiffDoc
      # Create a new WinRegDiffDoc object
      # [_metadata_] is a WinRegDiffMetadata object
      # [_regdiff_]  is a WinRegDiff object
      def initialize(metadata, regdiff)
        @metadata = metadata
        @key_add = regdiff.key_add
        @key_del = regdiff.key_del
        @val_add = regdiff.val_add
        @val_del = regdiff.val_del
        @val_mod = regdiff.val_mod

        @doc = REXML::Document.new
        decl = REXML::XMLDecl.new(nil, REXML::Encoding::UTF_8, true)
        @doc << decl
        @winregdiff = REXML::Element.new('winregdiff')
        @doc << @winregdiff

        baseline
        delta
        diffnode
        items_added
        items_deleted
        items_modified
      end

      # Write XML document to _fp_
      def write(fp)
        @doc.write(fp, 0, false, false)
        fp << "\n"
      end

      private
      def baseline
        baseline = REXML::Element.new('baseline')
        @winregdiff << baseline

        file = REXML::Element.new('file')
        baseline << file

        name = REXML::Element.new('name')
        name.add_text(@metadata.baseline)
        file << name

        sha = REXML::Element.new('sha')
        sha.add_text(@metadata.baseline_sha)
        file << sha
      end

      def delta
        delta = REXML::Element.new('delta')
        @winregdiff << delta

        file = REXML::Element.new('file')
        delta << file

        name = REXML::Element.new('name')
        name.add_text(@metadata.delta)
        file << name

        sha = REXML::Element.new('sha')
        sha.add_text(@metadata.delta_sha)
        file << sha

        app = REXML::Element.new('app')
        delta << app

        app_name = REXML::Element.new('name')
        app_name.add_text(@metadata.app_name)
        app << app_name

        nsrl = REXML::Element.new('nsrl')
        nsrl.add_text(@metadata.nsrl)
        app << nsrl

        action = REXML::Element.new('action')
        action.add_text(@metadata.action)
        app << action
      end

      def diffnode
        diffnode = REXML::Element.new('diffnode')
        @winregdiff << diffnode

        arch = REXML::Element.new('arch')
        arch.add_text(@metadata.arch)
        diffnode << arch

        sys = REXML::Element.new('sys')
        sys.add_text(@metadata.sys)
        diffnode << sys

        os = REXML::Element.new('os')
        os.add_text(@metadata.os)
        diffnode << os

        osver = REXML::Element.new('osver')
        osver.add_text(@metadata.osver)
        diffnode << osver

        user = REXML::Element.new('user')
        user.add_text(@metadata.user)
        diffnode << user

        time = REXML::Element.new('time')
        time.add_text(@metadata.time)
        diffnode << time
      end

      # helper method for items_added, items_deleted and items_modified
      def insert_keys(keys, subtree)
        keys.each do |clef|
          key = REXML::Element.new('key')
          subtree << key

          path = REXML::Element.new('path')
          path.add_text(clef.path)
          key << path
        end
      end

      # helper method for items_added, items_deleted and items_modified
      def insert_values(values, subtree) 
        values.each do |val|
          value = REXML::Element.new('value')
          subtree << value

          path = REXML::Element.new('path')
          path.add_text(val.path)
          value << path

          name = REXML::Element.new('name')
          name.add_text(val.name)
          value << name

          data = REXML::Element.new('data')

          begin
            cdata = REXML::CData.new(val.data) 
          rescue
            p(val)
          end

          data << cdata
          value << data
        end
      end
      private(:insert_keys, :insert_values)

      def items_added
        items_added = REXML::Element.new('add')
        @winregdiff << items_added
        insert_keys(@key_add, items_added)
        insert_values(@val_add, items_added)
      end

      def items_deleted
        items_deleted = REXML::Element.new('del')
        @winregdiff << items_deleted
        insert_keys(@key_del, items_deleted)
        insert_values(@val_del, items_deleted)
      end

      def items_modified
        items_modified = REXML::Element.new('mod')
        @winregdiff << items_modified
        insert_values(@val_mod, items_modified)
      end
    end
  end
end

