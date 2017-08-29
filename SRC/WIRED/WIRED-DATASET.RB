# == Synopsis
#
# A set of classes for creating the WIRED Dataset from a set of XML-based Registry differences
#
# == Usage
#
# Example:
#
#   require 'wired-dataset'
#   include Wired::Dataset
#   ...
#   ARGV.each do |fname|
#     ...
#     fp_input  = File.new(fname)
#     input_doc = Wired::Dataset::open_document(fp_input)
#     baseline  = Baseline.new(fname, input_doc)
#     delta     = Delta.new(fname, input_doc)
#     diffnode  = DiffNode.new(fname, input_doc)
#     ...
#     added = AddedEntries.new(fp_input, input_doc, baseline, delta, diffnode)
#     added.write(fp_output)
#     ...
#     deleted = DeletedEntries.new(fp_input, input_doc, baseline, delta, diffnode)
#     deleted.write(fp_output)
#     ...
#     modified = ModifiedEntries.new(fp_input, input_doc, baseline, delta, diffnode)
#     modified.write(fp_output)
#     ...
#   end
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

require 'rexml/document'

module Wired
  # Contains classes used to generate the WIRED Dataset from WIRED Registry Difference files in XML format
  module Dataset
    $wired_dataset_debug_mode = false

    def Dataset.set_debug_mode (mode)
      $wired_dataset_debug_mode = mode
    end

    def Dataset.format_error (in_file, script_line)
      raise Exception.new(sprintf("Error: %s(%d): Improper XML format for %s", $0, script_line, in_file))
    end

    def Dataset.file_error (file, script_line)
      raise Exception.new(sprintf("Error: %s(%d): Couldn't open file \"%s\" for I/0", $0, script_line, file))
    end

    # Returns a REXML::Document object from a File object containing a Registry difference in XML format
    def Dataset.open_document (fp)
      REXML::Document.new(fp)
    end

    # Represents the data contained in the baseline element of the registry difference
    class Baseline
      attr_reader :name, :sha

      # Create a new Baseline object
      # [_file_name_] Name of the difference file; used for error reporting
      # [_doc_]       REXML::Document object returned by Wired::Dataset#open_document
      def initialize (file_name, doc)
        begin
          @name = doc.root.elements["baseline/file/name"].text
          @sha  = doc.root.elements["baseline/file/sha"].text
        rescue
          Wired::Dataset::format_error(file_name, __LINE__)
        end
      end

      def Baseline.header
        $wired_dataset_debug_mode ? "BASELINE_NAME#{$;}BASELINE_SHA1" : ""
      end

      def to_s
        $wired_dataset_debug_mode ? sprintf("%s#{$;}%s", @name, @sha) : ""
      end
    end

    # Represents the data contained in the delta element of the registry difference
    class Delta
      attr_reader :name, :sha, :app, :nsrl, :action

      # Create a new Delta object
      # [_file_name_] Name of the difference file; used for error reporting
      # [_doc_]       REXML::Document object returned by Wired::Dataset#open_document
      def initialize (file_name, doc)
        begin
          @name   = doc.root.elements["delta/file/name"].text
          @sha    = doc.root.elements["delta/file/sha"].text
          @app    = doc.root.elements["delta/app/name"].text
          @nsrl   = doc.root.elements["delta/app/nsrl"].text
          @action = doc.root.elements["delta/app/action"].text
        rescue
          Wired::Dataset::format_error(file_name, __LINE__)
        end
      end

      def Delta.header
        tail = "APP_NAME#{$;}NSRL_APP_ID#{$;}ACTION" 
        $wired_dataset_debug_mode ? "DELTA_NAME#{$;}DELTA_SHA1#{$;}#{tail}" : tail
      end

      def to_s
        if $wired_dataset_debug_mode
          sprintf("%s#{$;}%s#{$;}%s#{$;}%s#{$;}%s", @name, @sha, @app, @nsrl, @action)
        else
          sprintf("%s#{$;}%s#{$;}%s", @app, @nsrl, @action)
        end
      end
    end

    # Represents the data contained in the diffnode element of the registry difference
    class DiffNode
      attr_reader :arch, :sys, :os, :osver, :user, :time

      # Create a new DiffNode object
      # [_file_name_] Name of the difference file; used for error reporting
      # [_doc_]       REXML::Document object returned by Wired::Dataset#open_document
      def initialize (file_name, doc)
        begin
          @arch  = doc.root.elements["diffnode/arch"].text
          @sys   = doc.root.elements["diffnode/sys"].text
          @os    = doc.root.elements["diffnode/os"].text
          @osver = doc.root.elements["diffnode/osver"].text
          @user  = doc.root.elements["diffnode/user"].text
          @time  = doc.root.elements["diffnode/time"].text
        rescue
          Wired::Dataset::format_error(file_name, __LINE__)
        end
      end

      def DiffNode.header
        $wired_dataset_debug_mode ? "ARCH#{$;}SYS#{$;}OS#{$;}OSVER#{$;}USER#{$;}TIME" : ""
      end

      def to_s
        $wired_dataset_debug_mode ? sprintf("%s#{$;}%s#{$;}%s#{$;}%s#{$;}%s#{$;}%s", @arch, @sys, @os, @osver, @user, @time) : ""
      end
    end

    # Pseudo-abstract parent class of Wired::RegKey and Wired::RegValue
    # <b>Internal use only</b>
    class RegEntry
      attr_reader :path
      def initialize (path)
        @path = path
      end

      def RegEntry.header
        "ENTRY_TYPE#{$;}PATH#{$;}VALUE_NAME#{$;}VALUE_DATA"
      end
    end

    # Represents the data contained in a key element of the registry difference
    # <b>Internal use only</b>
    class RegKey < RegEntry
      attr_reader :path
      def initialize (file_name, key_node)
        begin
          children = key_node.children.delete_if {|child| child.class == REXML::Text}
          path = children[0]
          super(path)
        rescue
          Wired::Dataset::format_error(file_name, __LINE__)
        end
      end

      def to_s
        sprintf("key#{$;}%s#{$;}#{$;}", @path.text)
      end
    end

    # Represents the data contained in a key element of the registry difference.
    # <b>Internal use only</b>
    class RegValue < RegEntry
      attr_reader :path, :name, :value
      def initialize (file_name, value_node)
        begin
          children = value_node.children.delete_if {|child| child.class == REXML::Text}
          path, @name, @data = children
          super(path)
        rescue
          Wired::Dataset::format_error(file_name, __LINE__)
        end
      end

      def to_s
        sprintf("value#{$;}%s#{$;}\%s#{$;}\%s", @path.text, @name.text, @data.text)
      end
    end

    # Represents a record in the WIRED dataset. Basically subclass objects are created for the sole purpose
    # of being printed to the output via Wired::Dataset::DatasetRecord#to_s
    # <b>Internal use only</b>
    class DatasetRecord
      ADD = 'add'
      DEL = 'del'
      MOD = 'del'
      attr_reader :baseline, :delta, :diffnode, :entry

      def initialize(baseline, delta, diffnode, entry)
        @baseline = baseline
        @delta    = delta
        @diffnode = diffnode
        @entry    = entry
      end

      def DatasetRecord.write_header(fp)
        header = "CHANGE_TYPE"
        [Baseline.header, Delta.header, DiffNode.header, RegEntry.header].each do |hdr|
          header << "#{$;}#{hdr}" if hdr != ""
        end
        fp.printf("%s\n", header)
      end

      def to_s
        row = nil
        [@baseline.to_s, @delta.to_s, @diffnode.to_s, @entry.to_s].each do |col|
          if row.nil?
            row = col if col != ""
          else
            row << "#{$;}#{col}" if col != ""
          end
        end
        row.nil? ? "" : row
      end
    end

    # Represents an entry (RegKey or RegValue) found as a child to the add element in the Registry Difference.
    # <b>Internal use only</b>
    class AddedEntry < DatasetRecord
      def initialize(baseline, delta, diffnode, entry)
        super
      end

      def to_s
        ADD + "#{$;}" + super
      end
    end

    # Represents an entry (RegKey or RegValue) found as a child to the del element in the Registry Difference.
    # <b>Internal use only</b>
    class DeletedEntry < DatasetRecord
      def initialize(baseline, delta, diffnode, entry)
        super
      end

      def to_s
        DEL + "#{$;}" + super
      end
    end

    # Represents an entry (RegKey or RegValue) found as a child to the mod element in the Registry Difference.
    # <b>Internal use only</b>
    class ModifiedEntry < DatasetRecord
      def initialize(baseline, delta, diffnode, entry)
        super
      end

      def to_s
        MOD + "#{$;}" + super
      end
    end

    # Pseudo-abstract parent class for AddedEntries, DeletedEntries and ModifiedEntries. <b>Internal use only</b>
    class ChangedEntries
      def initialize (file, doc, baseline, delta, diffnode)
        @file     = file
        @doc      = doc
        @baseline = baseline
        @delta    = delta
        @diffnode = diffnode
      end
    end

    # Represents all of the Registry entries found added in a Registry difference. AddedEntries#write does all of the real work;
    # just instantiate and use AddedEntries#write to output all of its records to the dataset file
    class AddedEntries < ChangedEntries
      # Creates a new AddedEntries object
      # [_file_]     Name of the difference file; used for error reporting
      # [_doc_]      REXML::Document object returned by Wired::Dataset#open_document
      # [_baseline_] see Baseline
      # [_delta_]    see Delta
      # [_diffnode_] see DiffNode
      def initialize (file, doc, baseline, delta, diffnode)
        super
      end
      
      def write (fp) 
        @doc.root.elements.each("//add/key") do |elem|
          key = RegKey.new(@file, elem)
          rec = AddedEntry.new(@baseline, @delta, @diffnode, key)
          fp.printf("%s#{$/}", rec)
        end

        @doc.root.elements.each("//add/value") do |elem|
          value = RegValue.new(@file, elem)
          rec = AddedEntry.new(@baseline, @delta, @diffnode, value)
          fp.printf("%s#{$/}", rec)
        end
      end
    end

    # Represents all of the Registry entries found deleted in a Registry difference. DeletedEntries#write does all of the real work;
    # just instantiate and use DeletedEntries#write to output all of its records to the dataset file
    class DeletedEntries < ChangedEntries
      # Creates a new DeletedEntries object
      # [_file_]     Name of the difference file; used for error reporting
      # [_doc_]      REXML::Document object returned by Wired::Dataset#open_document
      # [_baseline_] see Baseline
      # [_delta_]    see Delta
      # [_diffnode_] see DiffNode
      def initialize (file, doc, baseline, delta, diffnode)
        super
      end
      
      def write (fp) 
        @doc.root.elements.each("//del/key") do |elem|
          key = RegKey.new(@file, elem)
          rec = DeletedEntry.new(@baseline, @delta, @diffnode, key)
          fp.printf("%s#{$/}", rec)
        end

        @doc.root.elements.each("//del/value") do |elem|
          value = RegValue.new(@file, elem)
          rec = DeletedEntry.new(@baseline, @delta, @diffnode, value)
          fp.printf("%s#{$/}", rec)
        end
      end
    end

    # Represents all of the Registry entries found modified in a Registry difference. ModifiedEntries#write does all of the real work;
    # just instantiate and use ModifiedEntries#write to output all of its records to the dataset file
    class ModifiedEntries < ChangedEntries
      # Creates a new ModifiedEntries object
      # [_file_]     Name of the difference file; used for error reporting
      # [_doc_]      REXML::Document object returned by Wired::Dataset#open_document
      # [_baseline_] see Baseline
      # [_delta_]    see Delta
      # [_diffnode_] see DiffNode
      def initialize (file, doc, baseline, delta, diffnode)
        super
      end
      
      def write (fp) 
        @doc.root.elements.each("//mod/value") do |elem|
          value = RegValue.new(@file, elem)
          rec = ModifiedEntry.new(@baseline, @delta, @diffnode, value)
          fp.printf("%s#{$/}", rec)
        end
      end
    end
  end
end

