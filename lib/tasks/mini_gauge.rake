namespace :mini_gauge do
  
  desc "Create graphs of instances of classes and the example relations"
  task :graph do
    %w(doc:graph:environment_for_graph db:test:load doc:graph:clobber 
      doc:graph:generate_class_sources
      doc:graph:build_pdfs).collect do |task|
        
      Rake::Task[task].invoke
    end
  end
  
  namespace :graph do
    
    #The locations of where we place our files
    CLASS_ROOT = File.join(RAILS_ROOT, "doc", "graphs", "dot_sources", "classes") #Where the output plaintext goes for classes
    GRAPH_OUTPUT_ROOT = File.join(RAILS_ROOT, "doc", "graphs") # Where the png/pdf/whatever graphs go
        
    #Classes just inspect the class itself and it's relation, no data is included
    def saving_class(name, subfolders = []) 
      output_dir = File.join(CLASS_ROOT, *subfolders)
      FileUtils.mkdir_p(output_dir) unless File.directory?(output_dir)
      
      location = File.join(output_dir, name)
      File.open(location, "w") {|f| f.write( yield ) }
    end
    
    task :environment_for_graph do
      MiniGauge.enable!
      FakeoutAuthlogic.init      
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
      Rake::Task["doc:graph:clobber_sources"].invoke
      Rake::Task["doc:graph:clobber_output"].invoke
    end
      

    task :build_pdfs do
      raise "Cannot create graphs because the 'dot' command is not found" unless system("which dot")
            
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
    
  end   
end      
