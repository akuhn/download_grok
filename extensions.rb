

class Hash
  def method_missing(name, *args)
    fetch(name.to_s) { super }
  end
end

class String
  def to_proc
    @memoized_parts ||= self.split('.')
    ->(each) { each.dig(*@memoized_parts) }
  end
end