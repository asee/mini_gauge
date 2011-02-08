# Make this file available in your environment!  Copy it or add the following to a rakefile:
#
# Dir["#{Gem.searcher.find('mini_gauge').full_gem_path}/lib/tasks/*.rake"].each { |ext| load ext }
#

namespace :doc do
    
  namespace :mini_gauge do
    
    desc "Create graphs of instances of classes and the example relations"
    task :graph do
      %w(doc:mini_gauge:environment_for_graph db:test:load doc:mini_gauge:clobber 
        doc:mini_gauge:generate_class_sources doc:mini_gauge:generate_complete_graph
        doc:mini_gauge:build_pdfs).collect do |task|

        Rake::Task[task].invoke
      end
    end
    
    
    #The locations of where we place our files
    CLASS_ROOT = File.join(RAILS_ROOT, "doc", "graphs", "dot_sources", "classes") #Where the output plaintext goes for classes
    MODEL_ROOT = File.join(RAILS_ROOT, "doc", "graphs", "dot_sources", "models") #Where the output plaintext goes for models (ie, the ones with data)
    GRAPH_OUTPUT_ROOT = File.join(RAILS_ROOT, "doc", "graphs") # Where the png/pdf/whatever graphs go
            
    # A helper to save a model.  Models will include several instances of classes with data and demonstrate some relation
    def saving_model(name, subfolders = []) 
      output_dir = File.join(MODEL_ROOT, *subfolders)
      FileUtils.mkdir_p(output_dir) unless File.directory?(output_dir)
      
      location = File.join(output_dir, name)
      File.open(location, "w") {|f| f.write( yield ) }
    end
    
    
    #Classes just inspect the class itself and it's relation, no data is included
    def saving_class(name, subfolders = []) 
      output_dir = File.join(CLASS_ROOT, *subfolders)
      FileUtils.mkdir_p(output_dir) unless File.directory?(output_dir)
      
      location = File.join(output_dir, name)
      File.open(location, "w") {|f| f.write( yield ) }
    end
    
    task :environment_for_graph do
      if Rails && Rails.initialized? && RAILS_ENV != "test"
        raise "Rails environment already set to #{ENV["RAILS_ENV"] || RAILS_ENV}, graphs expect to be generated in test environment"
      end
      
      ENV["RAILS_ENV"] = "test"
      RAILS_ENV = "test"

      Rake::Task['environment'].invoke
      
      MiniGauge.enable!
    end
    
    desc "Remove the graph sources destination folders"
    task :clobber_sources do
      FileUtils.rm(Dir.glob(File.join(CLASS_ROOT,"**","*.dot"))) 
    end
    
    desc "Remove the graph sources destination folders"
    task :clobber_output do
      FileUtils.rm(Dir.glob(File.join(GRAPH_OUTPUT_ROOT,"**","*.pdf")))
    end
    
    desc "Remove all graphs and sources"
    task :clobber do
      Rake::Task["doc:mini_gauge:clobber_sources"].invoke
      Rake::Task["doc:mini_gauge:clobber_output"].invoke
    end
      

    task :build_pdfs do
      raise "Cannot create graphs because the 'dot' command is not found" unless system("which dot")
      
      Dir.glob(File.join(MODEL_ROOT,"**","*.dot")).each do |filename|
        destination = File.join(GRAPH_OUTPUT_ROOT, "models", filename.gsub(MODEL_ROOT,"").gsub(/\.dot$/,".pdf"))
        FileUtils.mkdir_p(File.dirname(destination))
        system("dot -Tpdf -o'#{destination}' '#{filename}'")
      end
            
      Dir.glob(File.join(CLASS_ROOT,"**","*.dot")).each do |filename|
        destination = File.join(GRAPH_OUTPUT_ROOT, "classes", filename.gsub(CLASS_ROOT,"").gsub(/\.dot$/,".pdf"))
        FileUtils.mkdir_p(File.dirname(destination))
        system("dot -Kcirco -Tpdf -o'#{destination}' '#{filename}'")
      end
      
    end

    task :generate_class_sources => :environment_for_graph do
      ActiveRecord::Base.send(:subclasses).each do |klass|
        namespace_parts = klass.name.split("::")
        saving_class("#{namespace_parts.pop.underscore}.dot", namespace_parts) do
          klass.to_dot_notation(:title => "#{klass.name} model associations")
        end
      end
    end
    
    task :generate_complete_graph => :environment_for_graph do
      saving_class("all_classes_in_app.dot") do
        @graph = MiniGauge::Graph.new(:title => "All classes in app", :description => "The complete set of classes and their relations")
        
        # No lazy loading here!
        Dir['app/models/**/*.rb'].each{|f| require f}
        
        # Run through all the reflections first in an attempt to load everything before getting all the subclasses.
        ActiveRecord::Base.send(:subclasses).each do |klass|
          begin klass.reflect_on_all_associations.each(&:klass) rescue nil end
        end
        
        ActiveRecord::Base.send(:subclasses).each do |klass|
          klass.add_to_graph(@graph)
        end

        @graph.to_dot_notation
        
      end
    end
    
  end   
end      
