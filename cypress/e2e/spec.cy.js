describe('Counter API Testing', () => {
  it('fetches the current count - GET', () => {
    cy.request('https://jl0b5q4gk9.execute-api.us-east-1.amazonaws.com/update_count').as('countRequest');
    cy.get('@countRequest').then( count => {
      expect(count.status).to.eq(200);
      expect(count.body.N).to.be.a('string')
    })
  })
})