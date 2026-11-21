import Foundation
@main struct Smoke {
 static func main() {
  assert(ApplicationState.submitted.frenchLabel == "Envoyée")
  assert(ApplicationState.rejected.frenchLabel == "Non retenue")
  assert(KutanaFormat.xaf(15000).contains("15"))
  let record = ListingRecord(id: UUID(), seller_id: UUID(), category: "Téléphones", title: "Téléphone", description: "Occasion", city: "Brazzaville", price_xaf: 15000, status: "published", created_at: Date())
  let data = try! JSONEncoder().encode(record)
  let copy = try! JSONDecoder().decode(ListingRecord.self, from: data)
  assert(copy.price_xaf == 15000)
  print("Domain smoke tests: OK")
 }
}
