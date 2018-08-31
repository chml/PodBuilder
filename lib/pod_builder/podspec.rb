module PodBuilder
  class Podspec
    class PodspecItem
      attr_accessor :name
      attr_accessor :module_name
      attr_accessor :vendored_frameworks
      attr_accessor :frameworks
      attr_accessor :weak_frameworks
      attr_accessor :libraries
      attr_accessor :resources
      attr_accessor :exclude_files

      def initialize
        @name = ""
        @module_name = ""
        @vendored_frameworks = []
        @frameworks = []
        @weak_frameworks = []
        @libraries = []
        @resources = []
        @exclude_files = []
      end

      def to_s
        @name
      end
    end
    private_constant :PodspecItem

    def self.generate(analyzer)     
      buildable_items = Podfile.podfile_items_at(PodBuilder::basepath("Podfile")).sort_by { |x| x.name }
      all_specs = buildable_items.map { |x| x.pod_specification(buildable_items) }

      podspec_items = []

      buildable_items.each do |pod|
        spec_exists = File.exist?(PodBuilder::basepath(vendored_spec_framework_path(pod))) 
        subspec_exists = File.exist?(PodBuilder::basepath(vendored_subspec_framework_path(pod)))
        
        unless spec_exists || subspec_exists
          puts "Skipping #{pod.name}, not prebuilt".blue
          next
        end

        pod_name = Configuration.subspecs_to_split.include?(pod.name) ? pod.name : pod.root_name
        unless podspec_item = podspec_items.detect { |x| x.name == pod_name }
          podspec_item = PodspecItem.new
          podspec_items.push(podspec_item)
          podspec_item.name = pod_name
          podspec_item.module_name = pod.module_name
        end
        
        podspec_item.vendored_frameworks += [pod] + pod.dependencies(buildable_items)

        podspec_item.frameworks = podspec_item.vendored_frameworks.map { |x| x.frameworks }.flatten.uniq.sort
        podspec_item.weak_frameworks = podspec_item.vendored_frameworks.map { |x| x.weak_frameworks }.flatten.uniq.sort
        podspec_item.libraries = podspec_item.vendored_frameworks.map { |x| x.libraries }.flatten.uniq.sort

        static_vendored_frameworks = podspec_item.vendored_frameworks.select { |x| x.is_static }
        
        podspec_item.resources = static_vendored_frameworks.map { |x| "#{vendored_framework_path(x)}/*.{nib,bundle,xcasset,strings,png,jpg,tif,tiff,otf,ttf,ttc,plist,json,caf,wav,p12,momd}" }.flatten.uniq
        podspec_item.exclude_files = static_vendored_frameworks.map { |x| "#{vendored_framework_path(x)}/Info.plist" }.flatten.uniq
      end

      podspecs = []
      podspec_items.each do |item|
        vendored_frameworks = item.vendored_frameworks.map { |x| vendored_framework_path(x) }.compact.uniq

        podspec = "  s.subspec '#{item.name.gsub("/", "_")}' do |p|\n"
        podspec += "    p.vendored_frameworks = '#{vendored_frameworks.join("','")}'\n"
        if item.frameworks.count > 0
          podspec += "    p.frameworks = '#{item.frameworks.join("', '")}'\n"
        end
        if item.libraries.count > 0
          podspec += "    p.libraries = '#{item.libraries.join("', '")}'\n"
        end
        if item.resources.count > 0
          podspec += "    p.resources = '#{item.resources.join("', '")}'\n"
        end
        if item.resources.count > 0
          podspec += "    p.exclude_files = '#{item.exclude_files.join("', '")}'\n"
        end
        podspec += "  end"

        podspecs.push(podspec)
      end
      
      cwd = File.dirname(File.expand_path(__FILE__))
      podspec_file = File.read("#{cwd}/templates/build_podspec.template")
      podspec_file.gsub!("%%%podspecs%%%", podspecs.join("\n\n"))

      platform = analyzer.result.targets.first.platform
      podspec_file.sub!("%%%platform_name%%%", platform.name)
      podspec_file.sub!("%%%deployment_version%%%", platform.deployment_target.version)
      
      File.write(PodBuilder::basepath("PodBuilder.podspec"), podspec_file)
    end
    
    private

    def self.vendored_framework_path(pod)
      if File.exist?(PodBuilder::basepath(vendored_subspec_framework_path(pod)))
        return vendored_subspec_framework_path(pod)
      elsif File.exist?(PodBuilder::basepath(vendored_spec_framework_path(pod)))
        return vendored_spec_framework_path(pod)
      end

      return nil
    end
    
    def self.vendored_subspec_framework_path(pod)
      return "Rome/#{pod.prebuilt_rel_path}"
    end

    def self.vendored_spec_framework_path(pod)
      return "Rome/#{pod.module_name}.framework"
    end
  end
end